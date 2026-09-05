/*
 * INAV target definition for GETFUN F722 V3.
 */

#include <stdint.h>

#include "platform.h"

#include "drivers/io.h"
#include "drivers/pwm_mapping.h"
#include "drivers/timer.h"

timerHardware_t timerHardware[] = {
    DEF_TIM(TIM2, CH1, PA15, TIM_USE_OUTPUT_AUTO, 0, 0), // S1
    // Use the alternate DMA streams for TIM1 channels so DShot output
    // channels do not contend for the default TIM1 DMA stream.
    DEF_TIM(TIM1, CH3, PA10, TIM_USE_OUTPUT_AUTO, 0, 1), // S2
    DEF_TIM(TIM1, CH2, PA9,  TIM_USE_OUTPUT_AUTO, 0, 1), // S3
    DEF_TIM(TIM1, CH1, PA8,  TIM_USE_OUTPUT_AUTO, 0, 1), // S4
    DEF_TIM(TIM8, CH4, PC9,  TIM_USE_OUTPUT_AUTO, 0, 0), // S5
    DEF_TIM(TIM8, CH3, PC8,  TIM_USE_OUTPUT_AUTO, 0, 0), // S6
    DEF_TIM(TIM2, CH4, PB11, TIM_USE_OUTPUT_AUTO, 0, 0), // S7
    DEF_TIM(TIM2, CH3, PB10, TIM_USE_OUTPUT_AUTO, 0, 0), // S8

    DEF_TIM(TIM3, CH4, PB1,  TIM_USE_LED,         0, 0), // WS2812 LED strip
};

const int timerHardwareCount = sizeof(timerHardware) / sizeof(timerHardware[0]);
