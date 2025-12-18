# Tests/GNUmakefile

# We need to find GNUstep Makefiles
include $(GNUSTEP_MAKEFILES)/common.make

# Add FreeType headers for FontConfig
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
FONTCONFIG_CFLAGS :=
else
FONTCONFIG_CFLAGS := -I/usr/include/freetype2
endif

# Name of our test bundle
BUNDLE_NAME = ScreenshotToolTests

# All test files will be included here
# For now, we'll start with a placeholder for the converted test
ScreenshotToolTests_OBJC_FILES = \
	CursorAssetProbe_test.m \
	ClipboardHighlighterOpacityProbe_test.m \
	ClipboardHighlighterProbe_test.m \
	CropUndoProbe_test.m \
	CropUndoWindowProbe_test.m \
	CursorRectProbe_test.m \
	HudCopyFeedbackProbe_test.m \
	StatusBarToggleProbe_test.m \
	TextFontComboProbe_test.m \
	ToolbarBadgeRefreshProbe_test.m \
	ToolbarIconThemeProbe_test.m \
	PopoverScaleFactorProbe_test.m \
	TooltipsSuppressedProbe_test.m \
	ZoomComboBoxProbe_test.m

# We also need to include the application's own source files to test them
# This path is relative to the Tests/ directory
ScreenshotToolTests_OBJC_FILES += \
	../Source/AppDelegate.m \
	../Source/ScreenshotCanvasView.m \
	../Source/MarkupStroke.m \
	../Source/MarkupText.m \
    ../Source/STFloatingPopover.m \
    ../Source/STFloatingPopoverWindow.m \
	../Source/STFloatingPopoverBackgroundView.m \
	../Source/STHyperlinkButton.m \
	../Source/STHudView.m \
	../Source/ScreenshotToolSettings.m \
	../Source/ToolSettingsPopoverController.m \
	../Source/TextToolPopoverController.m \
	../Source/PreferencesWindowController.m \
	../Source/STThemeUtilities.m

# We need to tell the compiler where to find the source headers
ADDITIONAL_OBJCFLAGS += -I../Source
ADDITIONAL_OBJCFLAGS += $(FONTCONFIG_CFLAGS)
ADDITIONAL_OBJCFLAGS += -fobjc-arc

# Include the bundle makefile
include $(GNUSTEP_MAKEFILES)/bundle.make
