include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = ScreenshotTool
ScreenshotTool_APPLICATION_ICON =

ScreenshotTool_RESOURCE_DIRS = Resources
ScreenshotTool_RESOURCE_FILES = Resources/CopyImage.png \
	Resources/Highligher.png \
	Resources/HighligherChangeColor.png \
	Resources/PenTool.png \
	Resources/PenChangeColor.png \
	Resources/Eraser.png \
	Resources/AddText.png \
	Resources/MarqueeTool.png \
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
	Resources/Preferences.png

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
	Source/STToolbarTooltipController.h

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
	Source/STToolbarTooltipController.m

CC = clang
ADDITIONAL_OBJCFLAGS += -fobjc-arc
ScreenshotTool_CPPFLAGS += -I/usr/include/freetype2
ADDITIONAL_LDFLAGS += -lfontconfig -lfreetype

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
	Source/STToolbarTooltipController.m

TEST_OUTPUT_DIR = Tests/bin
TESTS = CropUndoProbe CropUndoWindowProbe ClipboardHighlighterProbe ClipboardHighlighterOpacityProbe ToolbarBadgeRefreshProbe TooltipsSuppressedProbe
TEST_CLANG ?= clang
TEST_OBJCFLAGS := -fobjc-arc -ISource -I/usr/include/freetype2 $(shell gnustep-config --objc-flags)
TEST_LDFLAGS := $(shell gnustep-config --gui-libs) -lfontconfig -lfreetype

include $(GNUSTEP_MAKEFILES)/application.make

.PHONY: tests tests-only clean-tests

tests: $(TESTS:%=$(TEST_OUTPUT_DIR)/%)
	@mkdir -p $(HOME)/GNUstep/Defaults/.lck
	@set -e; \
	for tool in $(TESTS); do \
		echo "Running $$tool..."; \
		$(TEST_OUTPUT_DIR)/$$tool || exit 1; \
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

clean-tests:
	@rm -rf $(TEST_OUTPUT_DIR)

clean:: clean-tests
