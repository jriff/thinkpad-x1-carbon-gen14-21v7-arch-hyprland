CFLAGS_trace.o := -I$(src)
obj-m := typec_ucsi.o
typec_ucsi-y := ucsi.o
typec_ucsi-$(CONFIG_DEBUG_FS) += debugfs.o
typec_ucsi-$(CONFIG_TRACING) += trace.o
ifneq ($(CONFIG_POWER_SUPPLY),)
	typec_ucsi-y += psy.o
endif
ifneq ($(CONFIG_TYPEC_DP_ALTMODE),)
	typec_ucsi-y += displayport.o
endif
ifneq ($(CONFIG_TYPEC_TBT_ALTMODE),)
	typec_ucsi-y += thunderbolt.o
endif
