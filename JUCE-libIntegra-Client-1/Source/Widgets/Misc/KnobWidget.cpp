#include "JuceHeader.h"
#include "KnobWidget.h"

//==============================================================================
KnobWidget::KnobWidget ()
{
    Widget::setWidgetLabel ("Knob");

    slider.onValueChange = [this] { sliderAction (); };
    slider.setSliderStyle (Slider::SliderStyle::RotaryVerticalDrag);
    slider.setTextBoxStyle (Slider::NoTextBox, true, 0, 0);
    addAndMakeVisible (slider);

    slider.setColour (Slider::ColourIds::thumbColourId, Colours::limegreen);
    slider.setColour (Slider::ColourIds::rotarySliderOutlineColourId, Colours::lightgoldenrodyellow);
    slider.setColour (Slider::ColourIds::rotarySliderFillColourId, Colours::aquamarine.contrasting (0.2f));
}

KnobWidget::~KnobWidget () = default;

//==============================================================================
void KnobWidget::paint (Graphics& g)
{
    Widget::paint (g);
}

void KnobWidget::resized ()
{
    Widget::resized ();
    slider.setBounds (controllerBounds);
}

//==============================================================================
void KnobWidget::sliderAction ()
{
    std::cout << "KNOB TURNED: " + (String) slider.getValue () << std::endl;

}
