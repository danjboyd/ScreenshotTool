# Tests/GNUmakefile

# We need to find GNUstep Makefiles
include $(GNUSTEP_MAKEFILES)/common.make

# Add FreeType headers for FontConfig
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
FONTCONFIG_CFLAGS :=
else
ifneq ($(filter CLANG64,$(MSYSTEM)),)
FONTCONFIG_CFLAGS := -I/clang64/include/freetype2
else
FONTCONFIG_CFLAGS := -I/usr/include/freetype2
endif
endif

# Name of our test bundle
BUNDLE_NAME = ScreenshotToolTests

# tools-xctest is a submodule (danjboyd/tools-xctest); the top-level `make tests` builds its
# XCTest library and xctest tool first, and xctest runs this bundle (#61).
XCTEST_ROOT ?= $(abspath ../third_party/tools-xctest)
ifeq ($(wildcard $(XCTEST_ROOT)/XCTest/XCTestCase.m),)
$(error Missing tools-xctest at $(XCTEST_ROOT): run `git submodule update --init`)
endif

# All test files will be included here
# For now, we'll start with a placeholder for the converted test
ScreenshotToolTests_OBJC_FILES = \
	CursorAssetProbe_test.m \
	ArrowCalloutProbe_test.m \
	LaunchArgumentsProbe_test.m \
	LaunchWindowSizeProbe_test.m \
	EmptyStateProbe_test.m \
	LaunchCostProbe_test.m \
	TextMoveProbe_test.m \
	MultiWindowProbe_test.m \
	PasteAvailabilityProbe_test.m \
	PopoverFocusProbe_test.m \
	FitViewportRoundingProbe_test.m \
	TitleBarToolbarProbe_test.m \
	LowBitDepthImageProbe_test.m \
	ProjectFileProbe_test.m \
	ClipboardHighlighterOpacityProbe_test.m \
	ClipboardHighlighterProbe_test.m \
	CropClipsAnnotationsProbe_test.m \
	CropUndoProbe_test.m \
	CropUndoWindowProbe_test.m \
	FitToWindowProbe_test.m \
	CursorRectProbe_test.m \
	HudCopyFeedbackProbe_test.m \
	OpenImageToolbarRefreshProbe_test.m \
	ObjectSelectionProbe_test.m \
	OpenRecentProbe_test.m \
	PasteAsNewImageProbe_test.m \
	StatusBarToggleProbe_test.m \
	TextFontFacePopupProbe_test.m \
	ThemePreferenceProbe_test.m \
	ThemeSwitchProbe_test.m \
	TextAlignmentToolbarProbe_test.m \
	TextFontFieldProbe_test.m \
	TextStyleControlProbe_test.m \
	TextKeyboardPointerProbe_test.m \
	TextToolProbe_test.m \
	TextStyleExportProbe_test.m \
	TextFontComboProbe_test.m \
	ToolbarIconThemeProbe_test.m \
	PopoverScaleFactorProbe_test.m \
	TooltipsSuppressedProbe_test.m \
	UndoRedoToolbarProbe_test.m \
	WaylandClipboardMirrorProbe_test.m \
	WaylandPasteCheckProbe_test.m \
	ZoomToolbarWidthProbe_test.m \
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
	../Source/ZoomPopoverController.m \
	../Source/PreferencesWindowController.m \
	../Source/STTextOptionsBar.m \
	../Source/STFontFamilyList.m \
	../Source/STThemeUtilities.m


# We need to tell the compiler where to find the source headers
ADDITIONAL_OBJCFLAGS += -I../Source
ADDITIONAL_OBJCFLAGS += -I$(XCTEST_ROOT)
ADDITIONAL_OBJCFLAGS += $(FONTCONFIG_CFLAGS)
ADDITIONAL_OBJCFLAGS += -fobjc-arc
ADDITIONAL_OBJCFLAGS += -DHAVE_MODE_T
# AppDelegate links the vendored updater; the top-level build compiles these static libs first.
UPDATER_ROOT := $(abspath ../third_party/gnustep-packager-updater/objc)
ADDITIONAL_OBJCFLAGS += -I$(UPDATER_ROOT)/GPUpdaterCore/Headers
ADDITIONAL_OBJCFLAGS += -I$(UPDATER_ROOT)/GPUpdaterUI/Headers
ADDITIONAL_LIB_DIRS += -L$(UPDATER_ROOT)/GPUpdaterUI -L$(UPDATER_ROOT)/GPUpdaterCore
ScreenshotToolTests_BUNDLE_LIBS += -lGPUpdaterUI -lGPUpdaterCore
ADDITIONAL_LIB_DIRS += -L$(XCTEST_ROOT)/XCTest/obj
ScreenshotToolTests_BUNDLE_LIBS += -lXCTest
ifneq ($(filter CLANG64,$(MSYSTEM)),)
# gnustep-make links a Windows bundle's LDFLAGS inside -Wl,--whole-archive, which pulls in every
# member of these import libraries (and their duplicate __NULL_IMPORT_DESCRIPTORs); as bundle
# libraries they come after -Wl,--no-whole-archive.
ScreenshotToolTests_BUNDLE_LIBS += -lstdc++ -lobjc -lfontconfig -lfreetype -ldispatch
ADDITIONAL_LDFLAGS += -nostartfiles /clang64/lib/dllcrt2.o -Wl,--entry,DllMainCRTStartup
else
ADDITIONAL_LDFLAGS += -lstdc++
ADDITIONAL_LDFLAGS += -lobjc
ADDITIONAL_LDFLAGS += -lfontconfig -lfreetype -ldispatch
endif

# Include the bundle makefile
include $(GNUSTEP_MAKEFILES)/bundle.make
