include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = ScreenshotTool
ScreenshotTool_APPLICATION_ICON =

ScreenshotTool_RESOURCE_DIRS = Resources
ScreenshotTool_RESOURCE_FILES = Resources/CopyImage.png \
	Resources/CopyImage-light.png \
	Resources/CopyImage-dark.png \
	Resources/Highligher.png \
	Resources/Highligher-light.png \
	Resources/Highligher-dark.png \
	Resources/HighligherChangeColor.png \
	Resources/PenTool.png \
	Resources/PenTool-light.png \
	Resources/PenTool-dark.png \
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

ScreenshotTool_HEADERS = Source/AppDelegate.h \
	Source/ScreenshotCanvasView.h \
	Source/MarkupStroke.h \
	Source/MarkupText.h \
	Source/STFloatingPopover.h \
	Source/STFloatingPopoverWindow.h \
	Source/STFloatingPopoverBackgroundView.h \
	Source/STFloatingResizablePopover.h \
	Source/STHyperlinkButton.h \
	Source/ScreenshotToolSettings.h \
	Source/ToolSettingsPopoverController.h \
	Source/TextToolPopoverController.h \
	Source/PreferencesWindowController.h \
	Source/STToolbarTooltipController.h \
	Source/STThemeUtilities.h

ScreenshotTool_OBJC_FILES = Source/main.m \
	Source/AppDelegate.m \
	Source/ScreenshotCanvasView.m \
	Source/MarkupStroke.m \
	Source/MarkupText.m \
	Source/STFloatingPopover.m \
	Source/STFloatingPopoverWindow.m \
	Source/STFloatingPopoverBackgroundView.m \
	Source/STFloatingResizablePopover.m \
	Source/STHyperlinkButton.m \
	Source/ScreenshotToolSettings.m \
	Source/ToolSettingsPopoverController.m \
	Source/TextToolPopoverController.m \
	Source/PreferencesWindowController.m \
	Source/STToolbarTooltipController.m \
	Source/STThemeUtilities.m

CC = clang
ADDITIONAL_OBJCFLAGS += -fobjc-arc
ScreenshotTool_CPPFLAGS += -I/usr/include/freetype2
ADDITIONAL_LDFLAGS += -lfontconfig -lfreetype -ldispatch

TEST_SUPPORT_OBJC = Source/AppDelegate.m \
	Source/ScreenshotCanvasView.m \
	Source/MarkupStroke.m \
	Source/MarkupText.m \
	Source/STFloatingPopover.m \
	Source/STFloatingPopoverWindow.m \
	Source/STFloatingPopoverBackgroundView.m \
	Source/STFloatingResizablePopover.m \
	Source/STHyperlinkButton.m \
	Source/ScreenshotToolSettings.m \
	Source/ToolSettingsPopoverController.m \
	Source/TextToolPopoverController.m \
	Source/PreferencesWindowController.m \
	Source/STToolbarTooltipController.m \
	Source/STThemeUtilities.m

TEST_OUTPUT_DIR = Tests/bin
TESTS = CropUndoProbe CropUndoWindowProbe ClipboardHighlighterProbe ClipboardHighlighterOpacityProbe ToolbarBadgeRefreshProbe TooltipsSuppressedProbe ToolbarIconThemeProbe
TEST_CLANG ?= clang
GNUStepConfig ?= $(shell command -v gnustep-config 2>/dev/null)
ifeq ($(strip $(GNUStepConfig)),)
GNUStepConfig := /usr/GNUstep/System/Tools/gnustep-config
endif
ifeq ($(wildcard $(GNUStepConfig)),)
$(error Unable to locate gnustep-config; please install gnustep-make or add it to PATH)
endif
TEST_OBJCFLAGS := -fobjc-arc -ISource -I/usr/include/freetype2 $(shell $(GNUStepConfig) --objc-flags)
TEST_LDFLAGS := $(shell $(GNUStepConfig) --gui-libs) -lfontconfig -lfreetype -ldispatch

include $(GNUSTEP_MAKEFILES)/application.make

.PHONY: tests tests-only clean-tests

tests: $(TESTS:%=$(TEST_OUTPUT_DIR)/%)
	@mkdir -p $(HOME)/GNUstep/Defaults/.lck
	@set -e; \
	TEST_PATH_PREFIX="/usr/GNUstep/System/Tools"; \
	TEST_LD_PREFIX="/usr/GNUstep/System/Library/Libraries"; \
	if [ -n "$$PATH" ]; then \
		TEST_ENV_PATH="$$TEST_PATH_PREFIX:$$PATH"; \
	else \
		TEST_ENV_PATH="$$TEST_PATH_PREFIX"; \
	fi; \
	if [ -n "$$LD_LIBRARY_PATH" ]; then \
		TEST_ENV_LD="$$TEST_LD_PREFIX:$$LD_LIBRARY_PATH"; \
	else \
		TEST_ENV_LD="$$TEST_LD_PREFIX"; \
	fi; \
	for tool in $(TESTS); do \
		echo "Running $$tool..."; \
		PATH="$$TEST_ENV_PATH" LD_LIBRARY_PATH="$$TEST_ENV_LD" $(TEST_OUTPUT_DIR)/$$tool || exit 1; \
	done

tests-only:
	@$(MAKE) tests

$(TEST_OUTPUT_DIR):
	@mkdir -p $(TEST_OUTPUT_DIR)

$(TEST_OUTPUT_DIR)/CropUndoProbe: Tests/CropUndoProbe.m $(TEST_SUPPORT_OBJC) | $(TEST_OUTPUT_DIR)
	$(TEST_CLANG) $^ $(TEST_OBJCFLAGS) $(TEST_LDFLAGS) -o $@

$(TEST_OUTPUT_DIR)/CropUndoWindowProbe: Tests/CropUndoWindowProbe.m $(TEST_SUPPORT_OBJC) | $(TEST_OUTPUT_DIR)
	$(TEST_CLANG) $^ $(TEST_OBJCFLAGS) $(TEST_LDFLAGS) -o $@

$(TEST_OUTPUT_DIR)/ClipboardHighlighterProbe: Tests/ClipboardHighlighterProbe.m $(TEST_SUPPORT_OBJC) | $(TEST_OUTPUT_DIR)
	$(TEST_CLANG) $^ $(TEST_OBJCFLAGS) $(TEST_LDFLAGS) -o $@

$(TEST_OUTPUT_DIR)/ClipboardHighlighterOpacityProbe: Tests/ClipboardHighlighterOpacityProbe.m $(TEST_SUPPORT_OBJC) | $(TEST_OUTPUT_DIR)
	$(TEST_CLANG) $^ $(TEST_OBJCFLAGS) $(TEST_LDFLAGS) -o $@

$(TEST_OUTPUT_DIR)/ToolbarBadgeRefreshProbe: Tests/ToolbarBadgeRefreshProbe.m $(TEST_SUPPORT_OBJC) | $(TEST_OUTPUT_DIR)
	$(TEST_CLANG) $^ $(TEST_OBJCFLAGS) $(TEST_LDFLAGS) -o $@

$(TEST_OUTPUT_DIR)/TooltipsSuppressedProbe: Tests/TooltipsSuppressedProbe.m $(TEST_SUPPORT_OBJC) | $(TEST_OUTPUT_DIR)
	$(TEST_CLANG) $^ $(TEST_OBJCFLAGS) $(TEST_LDFLAGS) -o $@

$(TEST_OUTPUT_DIR)/ToolbarIconThemeProbe: Tests/ToolbarIconThemeProbe.m $(TEST_SUPPORT_OBJC) | $(TEST_OUTPUT_DIR)
	$(TEST_CLANG) $^ $(TEST_OBJCFLAGS) $(TEST_LDFLAGS) -o $@

clean-tests:
	@rm -rf $(TEST_OUTPUT_DIR)

clean:: clean-tests
