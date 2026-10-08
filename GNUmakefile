include $(GNUSTEP_MAKEFILES)/common.make

override OBJCFLAGS := $(filter-out -mbranch-protection=%,$(OBJCFLAGS))
override CFLAGS := $(filter-out -mbranch-protection=%,$(CFLAGS))

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
FONTCONFIG_CFLAGS :=
FONTCONFIG_LDFLAGS :=
else
ifneq ($(filter CLANG64,$(MSYSTEM)),)
FONTCONFIG_CFLAGS := -I/clang64/include/freetype2
FONTCONFIG_LDFLAGS := -lfontconfig -lfreetype -ldispatch
else
FONTCONFIG_CFLAGS := -I/usr/include/freetype2
FONTCONFIG_LDFLAGS := -lfontconfig -lfreetype -ldispatch
endif
endif

APP_NAME = ScreenshotTool
ScreenshotTool_APPLICATION_ICON =
UPDATER_ROOT := $(CURDIR)/third_party/gnustep-packager-updater/objc
UPDATER_CORE_DIR := $(UPDATER_ROOT)/GPUpdaterCore
UPDATER_UI_DIR := $(UPDATER_ROOT)/GPUpdaterUI
UPDATER_HELPER_DIR := $(UPDATER_ROOT)/gp-update-helper

ScreenshotTool_RESOURCE_DIRS =
ScreenshotTool_RESOURCE_FILES = Resources/CopyImage.png \
	Resources/CopyImage-symbolic.png \
	Resources/Highligher-symbolic.png \
	Resources/PenTool-symbolic.png \
	Resources/Arrow-symbolic.png \
	Resources/Eraser-symbolic.png \
	Resources/AddText-symbolic.png \
	Resources/MarqueeTool-symbolic.png \
	Resources/Preferences-symbolic.png \
	Resources/Undo-symbolic.png \
	Resources/Redo-symbolic.png \
	Resources/CopyImage-light.png \
	Resources/CopyImage-dark.png \
	Resources/Highligher.png \
	Resources/Highligher-light.png \
	Resources/Highligher-dark.png \
	Resources/HighligherChangeColor.png \
	Resources/PenTool.png \
	Resources/PenTool-light.png \
	Resources/PenTool-dark.png \
	Resources/Arrow.png \
	Resources/Arrow-light.png \
	Resources/Arrow-dark.png \
	Resources/PenChangeColor.png \
	Resources/Eraser.png \
	Resources/Eraser-light.png \
	Resources/Eraser-dark.png \
	Resources/AddText.png \
	Resources/AddText-light.png \
	Resources/AddText-dark.png \
	Resources/MarqueeTool.png \
	Resources/MarqueeTool-light.png \
	Resources/MarqueeTool-dark.png \
	Resources/Highligher-active.png \
	Resources/PenTool-active.png \
	Resources/Eraser-active.png \
	Resources/AddText-active.png \
	Resources/MarqueeTool-active.png \
	Resources/CopyImage-active.png \
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
	Resources/Preferences-dark.png

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
	Source/ZoomPopoverController.m \
	Source/PreferencesWindowController.m \
	Source/STTextOptionsBar.m \
	Source/STFontFamilyList.m \
	Source/STThemeUtilities.m \
	Source/STSegmentToolTips.m

CLANG_WRAPPER := $(shell pwd)/Tools/clang-wrapper.sh
CC = $(CLANG_WRAPPER)
ADDITIONAL_OBJCFLAGS += -fobjc-arc
ADDITIONAL_OBJCFLAGS += -DHAVE_MODE_T
ADDITIONAL_OBJCFLAGS += $(FONTCONFIG_CFLAGS)
ADDITIONAL_INCLUDE_DIRS += -I$(UPDATER_CORE_DIR)/Headers
ADDITIONAL_INCLUDE_DIRS += -I$(UPDATER_UI_DIR)/Headers
ADDITIONAL_LIB_DIRS += -L$(UPDATER_CORE_DIR)
ADDITIONAL_LIB_DIRS += -L$(UPDATER_UI_DIR)
ADDITIONAL_GUI_LIBS += -lGPUpdaterUI -lGPUpdaterCore
ADDITIONAL_LDFLAGS += $(FONTCONFIG_LDFLAGS)
ADDITIONAL_LDFLAGS += -lstdc++
ADDITIONAL_LDFLAGS += -lobjc



include $(GNUSTEP_MAKEFILES)/application.make

.PHONY: tests tests-only clean-tests updater-core updater-ui updater-helper

before-all:: updater-core updater-ui updater-helper

updater-core:
	@if [ ! -f "$(UPDATER_CORE_DIR)/Makefile" ]; then \
		echo "Vendored GPUpdaterCore sources are missing."; \
		exit 1; \
	fi
	@$(MAKE) -C "$(UPDATER_CORE_DIR)"

updater-ui:
	@if [ ! -f "$(UPDATER_UI_DIR)/Makefile" ]; then \
		echo "Vendored GPUpdaterUI sources are missing."; \
		exit 1; \
	fi
	@$(MAKE) -C "$(UPDATER_UI_DIR)"

updater-helper:
	@if [ ! -f "$(UPDATER_HELPER_DIR)/Makefile" ]; then \
		echo "Vendored gp-update-helper sources are missing."; \
		exit 1; \
	fi
	@$(MAKE) -C "$(UPDATER_HELPER_DIR)"

# tools-xctest (submodule) builds the XCTest library and the xctest tool that runs the bundle.
# Extra xctest options go in XCTEST_ARGS, e.g.
#   make tests XCTEST_ARGS="-only-testing:ScreenshotToolTests/FitViewportRoundingProbeTests"
XCTEST_ROOT := $(CURDIR)/third_party/tools-xctest
XCTEST_ARGS ?=
XCTEST_MAKE_ARGS :=
XCTEST_RUN_ENV :=
ifneq ($(filter CLANG64,$(MSYSTEM)),)
# libdispatch's os/generic_win_base.h (included by Foundation) defines mode_t unless told the C
# library already has; the app's makefiles pass the same flag.
XCTEST_MAKE_ARGS := ADDITIONAL_CPPFLAGS=-DHAVE_MODE_T
# Windows finds DLLs (XCTest.dll here) on PATH, not LD_LIBRARY_PATH.
XCTEST_RUN_ENV := PATH="$(XCTEST_ROOT)/XCTest/obj:$$PATH"
endif

tests:
	@echo "Building tools-xctest..."
	@$(MAKE) -C "$(XCTEST_ROOT)" $(XCTEST_MAKE_ARGS)
	@echo "Building test bundle..."
	@$(MAKE) -C Tests
	@echo "Running XCTest bundle..."
	@LD_LIBRARY_PATH="$(XCTEST_ROOT)/XCTest/obj$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}" \
		$(XCTEST_RUN_ENV) "$(XCTEST_ROOT)/obj/xctest" Tests/ScreenshotToolTests.bundle $(XCTEST_ARGS)

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
	@helper_source=""; \
	if [ -x "$(UPDATER_HELPER_DIR)/gp-update-helper" ]; then \
		helper_source="$(UPDATER_HELPER_DIR)/gp-update-helper"; \
	elif [ -x "$(UPDATER_HELPER_DIR)/gp-update-helper.exe" ]; then \
		helper_source="$(UPDATER_HELPER_DIR)/gp-update-helper.exe"; \
	fi; \
	if [ -n "$$helper_source" ]; then \
		cp "$$helper_source" ScreenshotTool.app/gp-update-helper; \
		if printf '%s' "$$helper_source" | grep -q '\.exe$$'; then \
			cp "$$helper_source" ScreenshotTool.app/gp-update-helper.exe; \
		fi; \
	else \
		echo "Warning: gp-update-helper was not built; packaged updater integration will be incomplete"; \
	fi

clean-tests:
	@echo "Cleaning test bundle..."
	@$(MAKE) -C Tests clean

clean:: clean-tests
	@$(MAKE) -C "$(UPDATER_HELPER_DIR)" clean
	@$(MAKE) -C "$(UPDATER_UI_DIR)" clean
	@$(MAKE) -C "$(UPDATER_CORE_DIR)" clean
