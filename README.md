# Yun-Sound-FPGA

基于 FPGA 的音乐合成器（FPGA-based music synthesizer）。项目包含传感器采集、实时音频合成、蓝牙通信、LED 演奏指引，以及配套的安卓演奏辅助 App。

## 提交内容

提交目录包含以下四类内容：

| 目录 | 内容 |
| --- | --- |
| `YUNSOUND代码/` | FPGA 完整工程，包括硬件逻辑源码、约束、构建脚本、仿真测试及构建报告。 |
| `App源码/` | 安卓 App 源码、界面资源、构建脚本及相关测试。 |
| `发布文件（apk和fs）/` | 可直接安装的 APK 和用于开发板下载或固化的 FPGA 配置文件。 |
| `验证记录/` | 数字仿真测试日志与数据。 |

## 文件结构

```text
.
├── YUNSOUND代码/
│   ├── rtl/                         # Verilog 硬件逻辑源码
│   ├── constraints/
│   │   ├── ads.cst                  # 物理引脚约束
│   │   └── audio.sdc                # 时序约束
│   ├── build_instrument.tcl         # 高云工具构建脚本
│   ├── scripts/
│   │   ├── build_all.py             # FPGA 自动构建与时序检查
│   │   ├── run_simulations.py       # 数字仿真运行脚本
│   │   └── analyze_spectrum.py      # 数字频谱分析
│   ├── tb/                          # Verilog 仿真测试台
│   ├── reports/
│   │   └── instrument/              # 工具输出报告
│   └── sim/                         # 仿真输出与日志（若包含）
├── App源码/
│   ├── src/                         # 安卓应用源码及原生接口逻辑
│   ├── assets/
│   │   └── index.html               # App 界面与交互逻辑
│   ├── res/                         # 应用图标等资源
│   ├── AndroidManifest.xml          # 安卓应用配置
│   ├── build.py                     # APK 构建与测试签名
│   ├── BUILD_INFO.json              # APK 构建信息
│   ├── test_chords.cjs              # 和弦功能测试
│   ├── test_layout.cjs              # 界面布局测试
│   ├── test_led.cjs                 # LED 指引交互测试
│   ├── test_reconstruction.cjs      # 波形重建测试
│   └── test_layout_results.json     # 界面布局测试结果
├── 发布文件（apk和fs）/
│   ├── *.apk                        # 平板 App 安装包
│   └── *.fs                         # FPGA 配置文件
└── 验证记录/                        # 数字仿真测试日志与数据
```

> `*.apk` 和 `*.fs` 表示文件类型，具体文件名以实际提交内容为准；`sim/` 为可能包含的目录。

## 一、YUNSOUND 代码

`YUNSOUND代码/` 为 FPGA 完整工程目录，包含硬件逻辑源码、引脚约束、构建脚本、仿真测试及构建报告。

### 硬件逻辑源码

`YUNSOUND代码/rtl/` 存放 Verilog 硬件逻辑源码，主要文件如下：

| 文件 | 功能说明 |
| --- | --- |
| `ads_instrument.v` | 工程顶层模块，定义开发板输入输出接口并连接系统核心。 |
| `ads_core.v` | 系统集成模块，连接传感器、合成引擎、音频输出、蓝牙、LED 及数码管。 |
| `mpr121_reader.v` | 电容触摸模块驱动，读取十二路触摸按键状态。 |
| `ads1115_reader.v` | ADS1115 驱动，配置 ADC 并轮询采集摇杆和压力信号。 |
| `ads_axis.v` | 摇杆输入校准、死区设置及归一化处理。 |
| `ads_pressure_map.v` | 压力信号映射与平滑处理。 |
| `performance_ui.v` | 开发板按键去抖，以及音色、效果和工作模式切换。 |
| `display_page.v` | 摇杆按键处理与八度选择。 |
| `performance_control.v` | 将演奏输入转换为音符触发、释放、变调及参数更新指令。 |
| `pitch_lut.v` | 音高相关查表。 |
| `expression_ratio.v` | 表情变调比例查表。 |
| `synth32_engine.v` | 音频合成核心，保存 128 组独立相位、频率和包络状态，通过共享硬件流水线完成逐样本计算与混音。 |
| `waveform.v` | 数学单周期波形查表。 |
| `audio_effects.v` | 延迟、合唱和混响效果处理。 |
| `codec_master_init.v` | WM8960 音频编解码器初始化及音频时钟状态检查。 |
| `i2s_codec_master.v` | 依据音频位时钟和帧时钟发送 I2S 音频样本。 |
| `lesson_guide.v` | 板上曲目指引逻辑。 |
| `score_ble.v` | 蓝牙控制命令解析、曲谱接收、跟练及远程 LED 目标处理。 |
| `score_status_tx.v` | 演奏状态与反馈数据的发送组织。 |
| `uart_rx.v`、`uart_tx.v` | UART 串口字节接收与发送。 |
| `visual_telemetry.v` | 波形、频点强度及李萨如图形配对数据提取。 |
| `led595_driver.v` | 74HC595 移位与锁存控制，驱动 LED 指引阵列。 |
| `seg_display.v` | 数码管显示驱动。 |
| `i2c_*.v` | I2C 通信辅助模块。 |

主工程实际参与构建的源文件以 `YUNSOUND代码/build_instrument.tcl` 中的文件列表为准。

### 约束、构建与验证文件

以下路径均相对于 `YUNSOUND代码/`：

| 路径 | 说明 |
| --- | --- |
| `constraints/ads.cst` | 物理引脚约束文件，定义各逻辑信号对应的 FPGA 引脚及电气属性。 |
| `constraints/audio.sdc` | 时序约束文件，定义系统时钟及相关接口时序要求。 |
| `build_instrument.tcl` | 高云工具构建脚本，指定目标器件、源文件、约束文件和顶层模块。 |
| `scripts/build_all.py` | FPGA 自动构建脚本，调用高云工具生成烧录文件并检查时序结果。 |
| `scripts/run_simulations.py` | 数字仿真运行脚本，编译并执行测试台。 |
| `scripts/analyze_spectrum.py` | 数字频谱分析脚本。 |
| `tb/` | Verilog 仿真测试台，用于检查合成引擎、力度控制、混音、效果器、通信及系统响应等功能。 |
| `reports/instrument/` | 综合、布局布线、资源占用、引脚和时序等工具输出报告。 |
| `sim/`（若包含） | 数字仿真输出与日志目录。 |

## 二、App 源码

`App源码/` 存放配套安卓应用的源码、资源、构建信息及测试文件。

以下路径均相对于 `App源码/`：

| 路径 | 说明 |
| --- | --- |
| `src/` | 安卓应用源码，包含应用入口及蓝牙通信等原生接口逻辑。 |
| `assets/index.html` | App 界面及交互逻辑，包含实时图形显示、曲谱编辑、跟练、演奏事件记录与曲谱导入导出。 |
| `res/` | 应用图标等资源文件。 |
| `AndroidManifest.xml` | 安卓应用配置文件，声明应用组件、权限及平台配置。 |
| `build.py` | APK 构建与测试签名脚本。 |
| `BUILD_INFO.json` | APK 构建信息，包含包名、文件校验值及平台配置等记录，以文件实际字段为准。 |
| `test_chords.cjs` | 和弦相关功能测试脚本。 |
| `test_layout.cjs` | 界面布局测试脚本。 |
| `test_led.cjs` | LED 指引相关交互测试脚本。 |
| `test_reconstruction.cjs` | 波形重建相关测试脚本。 |
| `test_layout_results.json` | 界面布局测试结果。 |

## 三、发布文件（apk和fs）

`发布文件（apk和fs）/` 存放可以直接安装或烧录的程序文件。

| 文件类型 | 用途 | 功能 |
| --- | --- | --- |
| `.apk` | 平板 App 安装包，用于安装蓝牙演奏辅助应用。 | 提供演奏状态显示、音频可视化、曲谱编辑、跟练及演奏事件记录等功能。 |
| `.fs` | FPGA 配置文件，用于将 YUNSOUND 代码对应的硬件逻辑下载或固化到开发板。 | 实现传感器采集、实时音频合成、蓝牙通信及 LED 控制等功能。 |

## 四、验证记录

`验证记录/` 存放数字仿真验证结果，包括力度响应、持续按键、混音及内部响应时间等测试日志和数据，用于说明相关逻辑在测试条件下的运行结果。
