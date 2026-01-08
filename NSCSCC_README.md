## 自己代码放置的位置

建议放置在仓库根目录 `mysrc` 目录下。

## 仿真

模板工程默认只提供了SOC整体测试，如需单元功能测试自行设计。

SOC整体仿真时，如需设定存储器初始数据，按需更改 `tb.sv` 中的 `BASE_RAM_INIT_FILE` 、`EXT_RAM_INIT_FILE` 、`FLASH_INIT_FILE` 等相应数据文件地址。
