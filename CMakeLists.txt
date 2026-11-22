# Custom behaviors in this repo (loaded as a Zephyr module via ZMK_EXTRA_MODULES).
# Behaviors run on the central (left) half only.
if ((NOT CONFIG_ZMK_SPLIT) OR CONFIG_ZMK_SPLIT_ROLE_CENTRAL)
  target_sources_ifdef(CONFIG_ZMK_BEHAVIOR_CALLUM_ONESHOT app PRIVATE src/behaviors/behavior_callum_oneshot.c)
endif()
