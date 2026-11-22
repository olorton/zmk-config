/*
 * One-shot modifiers, ported from Callum Oakley's QMK oneshot.c:
 * https://github.com/qmk/qmk_firmware/tree/user-keymaps-still-present/users/callum
 *
 * Usage: &osm LSHIFT (the parameter must be a modifier).
 *
 * As in Callum's version:
 *   - The modifier is sent as soon as the key is pressed.
 *   - Tapped (released unused), it is queued until the next non-modifier key is
 *     released. There is no timeout.
 *   - Used while held, it acts as a normal modifier.
 *   - Pressing a key in cancel-key-positions (NAV/SYM) cancels it.
 *   - Modifier keys and layer keys don't use it up, so one-shots stack and carry
 *     to the next key.
 *   - There is one state per modifier, shared by every key bound to it.
 */

#define DT_DRV_COMPAT zmk_behavior_callum_oneshot

#include <zephyr/device.h>
#include <drivers/behavior.h>
#include <zephyr/logging/log.h>

#include <zmk/behavior.h>
#include <zmk/event_manager.h>
#include <zmk/events/keycode_state_changed.h>
#include <zmk/events/position_state_changed.h>
#include <zmk/keys.h>

LOG_MODULE_DECLARE(zmk, CONFIG_ZMK_LOG_LEVEL);

#if DT_HAS_COMPAT_STATUS_OKAY(DT_DRV_COMPAT)

// Callum's oneshot_state
enum oneshot_state {
    OS_UP_UNQUEUED = 0,
    OS_UP_QUEUED,
    OS_DOWN_UNUSED,
    OS_DOWN_USED,
};

// One state per modifier: LCTRL, LSHIFT, LALT, LGUI, RCTRL, RSHIFT, RALT, RGUI.
#define MOD_COUNT 8
static enum oneshot_state states[MOD_COUNT];

struct behavior_callum_oneshot_config {
    size_t cancel_key_positions_len;
    uint32_t cancel_key_positions[];
};

static int mod_index(uint32_t encoded) {
    uint16_t page = ZMK_HID_USAGE_PAGE(encoded);
    uint16_t id = ZMK_HID_USAGE_ID(encoded);
    if (page == 0) {
        page = HID_USAGE_KEY;
    }
    if (!is_mod(page, id)) {
        return -EINVAL;
    }
    return id - HID_USAGE_KEY_KEYBOARD_LEFTCONTROL;
}

static void send_mod(int index, bool pressed, int64_t timestamp) {
    uint32_t keycode = HID_USAGE_KEY_KEYBOARD_LEFTCONTROL + index;
    raise_zmk_keycode_state_changed_from_encoded(ZMK_HID_USAGE(HID_USAGE_KEY, keycode), pressed,
                                                 timestamp);
}

// Trigger keydown
static int on_oneshot_binding_pressed(struct zmk_behavior_binding *binding,
                                      struct zmk_behavior_binding_event event) {
    int i = mod_index(binding->param1);
    if (i < 0) {
        LOG_ERR("callum_oneshot: parameter 0x%08X is not a modifier", binding->param1);
        return ZMK_BEHAVIOR_OPAQUE;
    }

    if (states[i] == OS_UP_UNQUEUED) {
        send_mod(i, true, event.timestamp);
    }
    states[i] = OS_DOWN_UNUSED;
    return ZMK_BEHAVIOR_OPAQUE;
}

// Trigger keyup
static int on_oneshot_binding_released(struct zmk_behavior_binding *binding,
                                       struct zmk_behavior_binding_event event) {
    int i = mod_index(binding->param1);
    if (i < 0) {
        return ZMK_BEHAVIOR_OPAQUE;
    }

    switch (states[i]) {
    case OS_DOWN_UNUSED:
        // Not used while held: queue it.
        states[i] = OS_UP_QUEUED;
        break;
    case OS_DOWN_USED:
        // Used while held: release it as normal.
        states[i] = OS_UP_UNQUEUED;
        send_mod(i, false, event.timestamp);
        break;
    default:
        break;
    }
    return ZMK_BEHAVIOR_OPAQUE;
}

static const struct behavior_driver_api behavior_callum_oneshot_driver_api = {
    .binding_pressed = on_oneshot_binding_pressed,
    .binding_released = on_oneshot_binding_released,
};

static int behavior_callum_oneshot_init(const struct device *dev) { return 0; }

#define OSM_INST(n)                                                                                \
    static const struct behavior_callum_oneshot_config behavior_callum_oneshot_config_##n = {      \
        .cancel_key_positions_len = DT_INST_PROP_LEN(n, cancel_key_positions),                     \
        .cancel_key_positions = DT_INST_PROP(n, cancel_key_positions),                             \
    };                                                                                             \
    BEHAVIOR_DT_INST_DEFINE(n, behavior_callum_oneshot_init, NULL, NULL,                           \
                            &behavior_callum_oneshot_config_##n, POST_KERNEL,                      \
                            CONFIG_KERNEL_INIT_PRIORITY_DEFAULT,                                   \
                            &behavior_callum_oneshot_driver_api);

DT_INST_FOREACH_STATUS_OKAY(OSM_INST)

#define OSM_CONFIG_PTR(n) &behavior_callum_oneshot_config_##n,
static const struct behavior_callum_oneshot_config *const all_configs[] = {
    DT_INST_FOREACH_STATUS_OKAY(OSM_CONFIG_PTR)};

static bool is_cancel_position(uint32_t position) {
    for (size_t c = 0; c < ARRAY_SIZE(all_configs); c++) {
        for (size_t p = 0; p < all_configs[c]->cancel_key_positions_len; p++) {
            if (all_configs[c]->cancel_key_positions[p] == position) {
                return true;
            }
        }
    }
    return false;
}

// Cancel key down: release every active one-shot (Callum's is_oneshot_cancel_key).
static void handle_position(const struct zmk_position_state_changed *ev) {
    if (!ev->state || !is_cancel_position(ev->position)) {
        return;
    }
    for (int i = 0; i < MOD_COUNT; i++) {
        if (states[i] != OS_UP_UNQUEUED) {
            states[i] = OS_UP_UNQUEUED;
            send_mod(i, false, ev->timestamp);
        }
    }
}

// Non-ignored key up: the one-shot has been used. Modifiers (including our own and other
// one-shots) are ignored, and layer keys send no keycodes, matching Callum's
// is_oneshot_ignored_key.
static void handle_keycode(const struct zmk_keycode_state_changed *ev) {
    if (ev->state || is_mod(ev->usage_page, ev->keycode)) {
        return;
    }
    int64_t timestamp = ev->timestamp;
    for (int i = 0; i < MOD_COUNT; i++) {
        switch (states[i]) {
        case OS_DOWN_UNUSED:
            states[i] = OS_DOWN_USED;
            break;
        case OS_UP_QUEUED:
            states[i] = OS_UP_UNQUEUED;
            send_mod(i, false, timestamp);
            break;
        default:
            break;
        }
    }
}

static int behavior_callum_oneshot_listener(const zmk_event_t *eh) {
    const struct zmk_position_state_changed *pos_ev = as_zmk_position_state_changed(eh);
    if (pos_ev != NULL) {
        handle_position(pos_ev);
        return ZMK_EV_EVENT_BUBBLE;
    }

    const struct zmk_keycode_state_changed *key_ev = as_zmk_keycode_state_changed(eh);
    if (key_ev != NULL) {
        handle_keycode(key_ev);
    }
    return ZMK_EV_EVENT_BUBBLE;
}

ZMK_LISTENER(behavior_callum_oneshot, behavior_callum_oneshot_listener);
ZMK_SUBSCRIPTION(behavior_callum_oneshot, zmk_position_state_changed);
ZMK_SUBSCRIPTION(behavior_callum_oneshot, zmk_keycode_state_changed);

#endif
