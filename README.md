Hummingbirdv2 E203 Core and SoC 
===============================

[![Deploy Documentation](https://github.com/riscv-mcu/e203_hbirdv2/workflows/Deploy%20Documentation/badge.svg)](https://doc.nucleisys.com/hbirdv2)

About
-----

This repository hosts the project for open-source Hummingbirdv2 E203 RISC-V processor Core and SoC, it's developped and opensourced by [Nuclei System Technology](www.nucleisys.com), the leading RISC-V IP and Solution company based on China Mainland.

This's an upgraded version of the project Hummingbird E203 maintained in [SI-RISCV/e200_opensource](https://github.com/SI-RISCV/e200_opensource), so we call it Hummingbirdv2 E203, and its architecture is shown in the figure below.
![hbirdv2](pics/hbirdv2_soc.JPG)


In this new version, we have following updates.
* Add NICE(Nuclei Instruction Co-unit Extension) for E203 core, so user could create customized HW co-units with E203 core easily.
* Integrate the APB interface peripherals(GPIO, I2C, UART, SPI, PWM) from [PULP Platform](https://github.com/pulp-platform) into Hummingbirdv2 SoC, these peripherals are implemented in Verilog language, so it's easy for user to understand. 
* Add new development boards(Nuclei ddr200t and mcu200t) support for Hummingbirdv2 SoC. 

**Welcome to visit https://github.com/riscv-mcu/hbird-sdk/ to use software development kit for the Hummingbird E203.**

**Welcome to visit https://www.rvmcu.com/community.html to participate in the discussion of the Hummingbird E203.**

**Welcome to visit http://www.rvmcu.com/ for more comprehensive information of availiable RISC-V MCU chips and embedded development.**


Detailed Introduction and Quick Start-up
----------------------------------------

We have provided very detailed introduction and quick start-up documents to help you ramping it up. 

The detailed introduction and the quick start documentation can be seen 
from https://doc.nucleisys.com/hbirdv2/.

By following the guidences from the doc, you can very easily start to use Hummingbirdv2 E203 processor Core and SoC.



