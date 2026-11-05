include ../AxsNeonPulseBuild.mk
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = AxsNeonPulsePrefs
AxsNeonPulsePrefs_FILES = $(wildcard *.m)
AxsNeonPulsePrefs_CFLAGS = -fobjc-arc -I../Sources
AxsNeonPulsePrefs_FRAMEWORKS = UIKit Foundation CoreFoundation
AxsNeonPulsePrefs_PRIVATE_FRAMEWORKS = Preferences
AxsNeonPulsePrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
