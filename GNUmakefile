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
	Source/PreferencesWindowController.h

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
	Source/PreferencesWindowController.m

CC = clang
ADDITIONAL_OBJCFLAGS += -fobjc-arc
ScreenshotTool_CPPFLAGS += -I/usr/include/freetype2
ADDITIONAL_LDFLAGS += -lfontconfig -lfreetype

include $(GNUSTEP_MAKEFILES)/application.make
