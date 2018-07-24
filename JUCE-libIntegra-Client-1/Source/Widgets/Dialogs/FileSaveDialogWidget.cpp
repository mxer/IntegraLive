#include "JuceHeader.h"
#include "FileSaveDialogWidget.h"

//==============================================================================
FileSaveDialogWidget::FileSaveDialogWidget ()
{
    Widget::setWidgetLabel ("Save File");

    button.setButtonText ("SAVE");
    button.onClick = [this] { displayFileDialog ("*.wav,*.mp3"); };

    addAndMakeVisible (button);
}

FileSaveDialogWidget::~FileSaveDialogWidget () = default;

//==============================================================================
void FileSaveDialogWidget::paint (Graphics& g)
{
    Widget::paint (g);
}

void FileSaveDialogWidget::resized ()
{
    Widget::resized ();
    button.setBounds (controllerBounds);
}

//==============================================================================
void FileSaveDialogWidget::displayFileDialog (StringRef extensionForFileToSave)
{
    FileChooser chooser ("Select A Sound File",
                         File::getSpecialLocation (File::userHomeDirectory),
                         extensionForFileToSave);

    if (chooser.browseForFileToSave (true))
    {
        auto file = chooser.getResult ();
        std::cout << file.getFullPathName () << std::endl;
    }

}
