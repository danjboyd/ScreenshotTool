include $(GNUSTEP_MAKEFILES)/common.make

override OBJCFLAGS := $(filter-out -mbranch-protection=%,$(OBJCFLAGS))
override CFLAGS := $(filter-out -mbranch-protection=%,$(CFLAGS))

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
FONTCONFIG_CFLAGS :=
FONTCONFIG_LDFLAGS :=
else
FONTCONFIG_CFLAGS := -I/usr/include/freetype2
FONTCONFIG_LDFLAGS := -lfontconfig -lfreetype -ldispatch
endif

APP_NAME = ScreenshotTool
ScreenshotTool_APPLICATION_ICON =

ScreenshotTool_RESOURCE_DIRS =
ScreenshotTool_RESOURCE_FILES = Resources/CopyImage.png \
	Resources/CopyImage-light.png \
	Resources/CopyImage-dark.png \
	Resources/CopyImage-light-gnustep.png \
	Resources/CopyImage-dark-gnustep.png \
	Resources/Highligher.png \
	Resources/Highligher-light.png \
	Resources/Highligher-dark.png \
	Resources/Highligher-light-gnustep.png \
	Resources/Highligher-dark-gnustep.png \
	Resources/HighligherChangeColor.png \
	Resources/PenTool.png \
	Resources/PenTool-light.png \
	Resources/PenTool-dark.png \
	Resources/PenTool-light-gnustep.png \
	Resources/PenTool-dark-gnustep.png \
	Resources/PenChangeColor.png \
	Resources/Eraser.png \
	Resources/Eraser-light.png \
	Resources/Eraser-dark.png \
	Resources/Eraser-light-gnustep.png \
	Resources/Eraser-dark-gnustep.png \
	Resources/AddText.png \
	Resources/AddText-light.png \
	Resources/AddText-dark.png \
	Resources/AddText-light-gnustep.png \
	Resources/AddText-dark-gnustep.png \
	Resources/AddText-light-active-gnustep.png \
	Resources/AddText-dark-active-gnustep.png \
	Resources/MarqueeTool.png \
	Resources/MarqueeTool-light.png \
	Resources/MarqueeTool-dark.png \
	Resources/MarqueeTool-light-gnustep.png \
	Resources/MarqueeTool-dark-gnustep.png \
	Resources/MarqueeTool-light-active-gnustep.png \
	Resources/MarqueeTool-dark-active-gnustep.png \
	Resources/Highligher-active.png \
	Resources/Highligher-light-active-gnustep.png \
	Resources/Highligher-dark-active-gnustep.png \
	Resources/PenTool-active.png \
	Resources/PenTool-light-active-gnustep.png \
	Resources/PenTool-dark-active-gnustep.png \
	Resources/Eraser-active.png \
	Resources/Eraser-light-active-gnustep.png \
	Resources/Eraser-dark-active-gnustep.png \
	Resources/AddText-active.png \
	Resources/MarqueeTool-active.png \
	Resources/CopyImage-active.png \
	Resources/CopyImage-light-active-gnustep.png \
	Resources/CopyImage-dark-active-gnustep.png \
	Resources/CopyImage.tiff \
	Resources/ScreenshotToolIcon.png \
	Resources/ScreenshotToolIcon.tiff \
	Resources/Highligher.tiff \
	Resources/HighligherChangeColor.tiff \
	Resources/PenTool.tiff \
	Resources/PenChangeColor.tiff \
	Resources/Eraser.tiff \
	Resources/AddText-active.tiff \
	Resources/MarqueeTool-active.tiff \
	Resources/Highligher-active.tiff \
	Resources/PenTool-active.tiff \
	Resources/Eraser-active.tiff \
	Resources/CopyImage-active.tiff \
	Resources/Preferences.png \
	Resources/Preferences-light.png \
	Resources/Preferences-dark.png \
	Resources/Preferences-light-gnustep.png \
	Resources/Preferences-dark-gnustep.png \
	Resources/Preferences-light-active-gnustep.png \
	Resources/Preferences-dark-active-gnustep.png

ScreenshotTool_RESOURCE_FILES += \
	Resources/Cursors/pen-cursor@1x.png \
	Resources/Cursors/pen-cursor@1x.tiff \
	Resources/Cursors/pen-cursor@2x.png \
	Resources/Cursors/pen-cursor@2x.tiff \
	Resources/Cursors/highlighter-cursor@1x.png \
	Resources/Cursors/highlighter-cursor@1x.tiff \
	Resources/Cursors/highlighter-cursor@2x.png \
	Resources/Cursors/highlighter-cursor@2x.tiff \
	Resources/Cursors/eraser-cursor@1x.png \
	Resources/Cursors/eraser-cursor@1x.tiff \
	Resources/Cursors/eraser-cursor@2x.png \
	Resources/Cursors/eraser-cursor@2x.tiff \
	Resources/Cursors/marquee-cursor@1x.png \
	Resources/Cursors/marquee-cursor@1x.tiff \
	Resources/Cursors/marquee-cursor@2x.png \
	Resources/Cursors/marquee-cursor@2x.tiff \
	Resources/Cursors/markup-cursors.metadata.json

ScreenshotTool_GSWAPP_INFO_PLIST = Resources/Info-gnustep.plist

ScreenshotTool_HEADERS = Source/AppDelegate.h \
	Source/ScreenshotCanvasView.h \
	Source/MarkupStroke.h \
	Source/MarkupText.h \
	Source/STFloatingPopover.h \
	Source/STFloatingPopoverWindow.h \
    Source/STFloatingPopoverBackgroundView.h \
	Source/STHyperlinkButton.h \
	Source/STHudView.h \
	Source/ScreenshotToolSettings.h \
	Source/ToolSettingsPopoverController.h \
	Source/TextToolPopoverController.h \
	Source/PreferencesWindowController.h \
	Source/STThemeUtilities.h

ScreenshotTool_OBJC_FILES = Source/main.m \
	Source/AppDelegate.m \
	Source/ScreenshotCanvasView.m \
	Source/MarkupStroke.m \
	Source/MarkupText.m \
    Source/STFloatingPopover.m \
    Source/STFloatingPopoverWindow.m \
    Source/STFloatingPopoverBackgroundView.m \
	Source/STHyperlinkButton.m \
	Source/STHudView.m \
	Source/ScreenshotToolSettings.m \
	Source/ToolSettingsPopoverController.m \
	Source/TextToolPopoverController.m \
	Source/PreferencesWindowController.m \
	Source/STThemeUtilities.m

CLANG_WRAPPER := $(shell pwd)/tools/clang-wrapper.sh
CC = $(CLANG_WRAPPER)
ADDITIONAL_OBJCFLAGS += -fobjc-arc
ScreenshotTool_CPPFLAGS += $(FONTCONFIG_CFLAGS)
ADDITIONAL_LDFLAGS += $(FONTCONFIG_LDFLAGS)



include $(GNUSTEP_MAKEFILES)/application.make

.PHONY: tests tests-only clean-tests

tests:
	@echo "Building test bundle..."
	@$(MAKE) -C Tests
	@echo "Running XCTest bundle..."
	@xctest Tests/ScreenshotToolTests.bundle

tests-only:
	@$(MAKE) tests



after-all:: Resources/Info-gnustep.plist
	@if [ -d ScreenshotTool.app/Resources ]; then \
		cp Resources/Info-gnustep.plist ScreenshotTool.app/Resources/Info-gnustep.plist; \
	elif [ -d ScreenshotTool.app/Contents/Resources ]; then \
		cp Resources/Info-gnustep.plist ScreenshotTool.app/Contents/Resources/Info-gnustep.plist; \
	else \
		echo "Warning: could not locate bundle Resources directory to copy Info-gnustep.plist"; \
	fi

clean-tests:
	@echo "Cleaning test bundle..."
	@$(MAKE) -C Tests clean

clean:: clean-tests
