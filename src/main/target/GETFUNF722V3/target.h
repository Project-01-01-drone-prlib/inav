/*
 * INAV target definition for GETFUN F722 V3.
 *
 * Pin assignments and feature defaults are based on:
 * /home/px4/01-bf/2-betaflight/src/config/configs/GFUN/GETFUNF722V3/config.h
 */

#pragma once

#define TARGET_BOARD_IDENTIFIER "GF72"
#define USBD_PRODUCT_STRING      "GETFUNF722V3"

// Board indicators
#define LED0                    PC15
#define LED1                    PC14

#define USE_BEEPER
#define BEEPER                  PB0
#define BEEPER_INVERTED

// USB and serial ports
#define USB_IO
#define USE_VCP

#define USE_UART1
#define UART1_TX_PIN            PB6
#define UART1_RX_PIN            PB7

#define USE_UART2
#define UART2_TX_PIN            PA2
#define UART2_RX_PIN            PA3

#define USE_UART3
#define UART3_TX_PIN            PC10
#define UART3_RX_PIN            PC11

#define USE_UART4
#define UART4_TX_PIN            PA0
#define UART4_RX_PIN            PA1

#define USE_UART5
#define UART5_TX_PIN            PC12
#define UART5_RX_PIN            PD2

#define USE_UART6
#define UART6_TX_PIN            PC6
#define UART6_RX_PIN            PC7

#define SERIAL_PORT_COUNT       7

#define DEFAULT_RX_TYPE         RX_TYPE_SERIAL
#define SERIALRX_PROVIDER       SERIALRX_SBUS
#define SERIALRX_UART           SERIAL_PORT_USART3
#define GPS_UART                SERIAL_PORT_USART6
#define MSP_UART                SERIAL_PORT_USART2
#define MSP_DISPLAYPORT_UART    SERIAL_PORT_UART4

// SPI1: ICM42688P (INAV uses the ICM42605 driver/descriptor for this device)
#define USE_SPI
#define USE_SPI_DEVICE_1
#define SPI1_SCK_PIN            PA5
#define SPI1_MISO_PIN           PA6
#define SPI1_MOSI_PIN           PA7

#define USE_IMU_ICM42605
#define IMU_ICM42605_ALIGN      CW90_DEG
#define ICM42605_CS_PIN         PA4
#define ICM42605_SPI_BUS        BUS_SPI1

// SPI2: MAX7456 analog OSD
#define USE_SPI_DEVICE_2
#define SPI2_SCK_PIN            PB13
#define SPI2_MISO_PIN           PB14
#define SPI2_MOSI_PIN           PB15

#define USE_MAX7456
#define MAX7456_SPI_BUS         BUS_SPI2
#define MAX7456_CS_PIN          PB12

// SPI3: W25Q128FV (supported by the M25P16-compatible INAV flash driver)
#define USE_SPI_DEVICE_3
#define SPI3_SCK_PIN            PB3
#define SPI3_MISO_PIN           PB4
#define SPI3_MOSI_PIN           PB5

#define USE_FLASHFS
#define USE_FLASH_M25P16
#define M25P16_SPI_BUS          BUS_SPI3
#define M25P16_CS_PIN           PC13
#define ENABLE_BLACKBOX_LOGGING_ON_SPIFLASH_BY_DEFAULT

// I2C1: DPS310 and external magnetometer
#define USE_I2C
#define USE_I2C_DEVICE_1
#define I2C1_SCL                PB8
#define I2C1_SDA                PB9

#define USE_BARO
#define USE_BARO_DPS310
#define BARO_I2C_BUS            BUS_I2C1

#define USE_MAG
#define USE_MAG_ALL
#define MAG_I2C_BUS             BUS_I2C1

// External MSP optical-flow and rangefinder interfaces.  The MT-specific
// Betaflight driver names are not present in this INAV revision.
#define USE_OPFLOW
#define USE_OPFLOW_MSP
#define USE_RANGEFINDER
#define USE_RANGEFINDER_MSP

// ADC3
#define USE_ADC
#define ADC_INSTANCE                ADC3
#define ADC3_DMA_OPT                0
#define ADC_CHANNEL_1_PIN           PC0
#define ADC_CHANNEL_2_PIN           PC1
#define ADC_CHANNEL_3_PIN           PC2
#define VBAT_ADC_CHANNEL            ADC_CHN_1
#define CURRENT_METER_ADC_CHANNEL   ADC_CHN_2
#define RSSI_ADC_CHANNEL            ADC_CHN_3

// PINIO power controls: PINIO2 is inverted in the Betaflight reference.
#define USE_PINIO
#define USE_PINIOBOX
#define PINIO1_PIN                  PC4
#define PINIO2_PIN                  PB2
#define PINIO2_FLAGS                PINIO_FLAGS_INVERTED

#define USE_LED_STRIP
#define WS2811_PIN                  PB1

#define DEFAULT_FEATURES            (FEATURE_OSD | FEATURE_TELEMETRY | FEATURE_CURRENT_METER | FEATURE_VBAT | FEATURE_GPS | FEATURE_BLACKBOX)
#define DEFAULT_BLACKBOX_DEVICE    BLACKBOX_DEVICE_FLASH
#define DEFAULT_POSHOLD_POSITION_SOURCE POSHOLD_SOURCE_AUTO
#define DEFAULT_ALTITUDE_SOURCE    ALTITUDE_SOURCE_RANGEFINDER_PREFER
#define DEFAULT_DSHOT_BURST        DSHOT_DMAR_ON
#define DEFAULT_CURRENT_METER_SOURCE CURRENT_METER_ADC
#define DEFAULT_VOLTAGE_METER_SOURCE VOLTAGE_METER_ADC
#define DEFAULT_CURRENT_METER_SCALE 100
#define DEFAULT_VOLTAGE_METER_SCALE 110
#define DEFAULT_PID_PROCESS_DENOM  4

#define USE_SERIAL_4WAY_BLHELI_INTERFACE
#define USE_DSHOT
#define USE_ESC_SENSOR

#define TARGET_IO_PORTA         0xffff
#define TARGET_IO_PORTB         0xffff
#define TARGET_IO_PORTC         0xffff
#define TARGET_IO_PORTD         0xffff
#define TARGET_IO_PORTE         0xffff
#define TARGET_IO_PORTF         0xffff

#define MAX_PWM_OUTPUT_PORTS    8
