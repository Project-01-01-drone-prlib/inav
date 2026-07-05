# 定高掉高与 AGL 垂向速度估计排查总结

## 背景

这份笔记总结从自稳切定高、光流定点、ToF AGL 估计、油门输入、垂向速度环一路排查下来的结论。

核心现象是：

- 自稳切到定高或定点后，飞机有掉高和抖动。
- 在部分日志里，飞手已经上推油门，`rcData[3]` 增大，但 `surfaceRaw` / `navPos[2]` 仍然持续下降。
- 高度目标 `navTgtPos[2]` 有时是稳定的，问题不总是来自目标高度跳变。
- 后续日志显示，关键矛盾集中到 AGL 垂向速度估计：真实 ToF 高度在下降，但 `navVel[2]` / `debug[3]` 经常显示接近 0 或正值。

## 相关代码路径

### 高度控制进入方式

多旋翼高度控制主要在：

- `src/main/navigation/navigation_multicopter.c`
- `src/main/navigation/navigation.c`

进入带高度控制的导航状态后，系统会初始化当前高度目标，并根据当前模式决定是否由油门杆进入高度调整。

`navFlags` 中和本次排查最相关的是：

- 低位若干 bit 代表导航高度/位置控制状态有效。
- bit 7 对应 `posControl.flags.isAdjustingAltitude`。

代码位置：

```c
if (posControl.flags.isAdjustingAltitude) navFlags |= (1 << 7);
```

因此：

- `navFlags = 47` 时，bit 7 没置位，垂向通常是位置环生成目标速度。
- `navFlags = 175` 时，bit 7 置位，说明油门杆正在调整高度，垂向目标速度主要来自 stick 输入。

### 油门杆到目标爬升速度

油门输入判断在 `adjustMulticopterAltitudeFromRCInput()` 中：

```c
const uint8_t deadband = rcControlsConfig()->alt_hold_deadband;
const int16_t rcThrottleAdjustment = applyDeadband(rcCommand[THROTTLE] - altHoldThrottleRCZero, deadband);
```

当 `rcThrottleAdjustment != 0` 时：

```c
const int16_t rcClimbRate = rcThrottleAdjustment * navConfig()->mc.max_manual_climb_rate / controlRange;
targetVel.z = rcClimbRate;
```

所以：

- `rcData[3]` 是接收机原始油门。
- `rcCommand[3]` 是经过油门曲线、导航层处理后的内部油门命令。
- `altHoldThrottleRCZero` 是定高油门杆零点。
- `deadband` 来自 `alt_hold_deadband`。
- stick 调高时，最终影响 `navTgtVel[2]`。

### 垂向速度闭环

高度方向最终不是直接用 `navTgtPos[2]` 控油门，而是经过：

```text
目标高度 -> 目标速度 -> 速度误差 -> 油门输出
```

在 `navFlags = 47` 时，通常是高度位置误差生成 `navTgtVel[2]`。

在 `navFlags = 175` 时，stick 输入直接生成 `navTgtVel[2]`。

速度环看的核心误差是：

```text
navTgtVel[2] - navVel[2]
```

因此，如果 `navVel[2]` 估计错了，即使飞手上推油门，速度环也可能认为“当前已经在上升”，从而不给足油门。

## 已加入的调试字段

### `DEBUG_ALTITUDE`

在 `src/main/navigation/navigation_multicopter.c` 中加入了高度油门输入判断变量：

```c
DEBUG_SET(DEBUG_ALTITUDE, 4, altHoldDebugRcCommand);
DEBUG_SET(DEBUG_ALTITUDE, 5, altHoldDebugRcZero);
DEBUG_SET(DEBUG_ALTITUDE, 6, altHoldDebugDeadband);
DEBUG_SET(DEBUG_ALTITUDE, 7, altHoldDebugAdjustment);
```

用于确认：

- `debug[4]`: `rcCommand[THROTTLE]`
- `debug[5]`: `altHoldThrottleRCZero`
- `debug[6]`: `alt_hold_deadband`
- `debug[7]`: `rcThrottleAdjustment`

切换方式：

```text
set debug_mode = ALTITUDE
save
```

### `DEBUG_AGL`

在 `src/main/navigation/navigation_pos_estimator_agl.c` 中加入了 AGL 估计相关变量：

```c
DEBUG_SET(DEBUG_AGL, 0, posEstimator.surface.reliability * 1000);
DEBUG_SET(DEBUG_AGL, 1, posEstimator.est.aglQual);
DEBUG_SET(DEBUG_AGL, 2, posEstimator.est.aglAlt);
DEBUG_SET(DEBUG_AGL, 3, posEstimator.est.aglVel);
DEBUG_SET(DEBUG_AGL, 4, posEstimator.surface.alt);
DEBUG_SET(DEBUG_AGL, 5, posEstimator.surface.alt - posEstimator.est.aglAlt);
DEBUG_SET(DEBUG_AGL, 6, posEstimator.est.vel.z);
DEBUG_SET(DEBUG_AGL, 7, posEstimator.imu.accelNEU.z);
```

用于确认：

- `debug[0]`: surface reliability * 1000
- `debug[1]`: AGL quality
- `debug[2]`: `aglAlt`
- `debug[3]`: `aglVel`
- `debug[4]`: ToF / surface 高度
- `debug[5]`: surface residual
- `debug[6]`: 全局高度估计速度 `est.vel.z`
- `debug[7]`: 导航估计器实际使用的 NEU Z 轴加速度 `imu.accelNEU.z`

切换方式：

```text
set debug_mode = AGL
save
```

黑匣子里的 `navAcc[2]` 和 `debug[7]` 是同一条关键状态：

```c
posEstimator.imu.accelNEU.z = accelReading.z + posEstimator.imu.accelBias.z;
navAccNEU[Z] = posEstimator.imu.accelNEU.z;
```

## AGL 速度估计链路

AGL 估计在 `src/main/navigation/navigation_pos_estimator_agl.c`。

核心预测部分：

```c
posEstimator.est.aglAlt += posEstimator.est.aglVel * ctx->dt;
posEstimator.est.aglAlt += posEstimator.imu.accelNEU.z * sq(ctx->dt) / 2.0f * posEstimator.imu.accWeightFactor;
posEstimator.est.aglVel += posEstimator.imu.accelNEU.z * ctx->dt * posEstimator.imu.accWeightFactor;
```

ToF 修正部分：

```c
posEstimator.est.aglAlt += surfaceResidual * w_z_surface_p * ... * ctx->dt;
posEstimator.est.aglVel += surfaceResidual * w_z_surface_v * ... * ctx->dt;
```

所以 AGL 高度和速度来自两类信息：

- IMU 垂向加速度积分。
- ToF surface residual 对高度和速度的修正。

本次排查的关键发现是：

- ToF 高度 `surfaceRaw` / `debug[4]` 和 `aglAlt` / `debug[2]` 大体贴合。
- 但 `aglVel` / `debug[3]` / `navVel[2]` 经常和 ToF 高度变化方向不一致。
- 主要矛盾不是 ToF 高度本身，而是 IMU 垂向加速度把速度状态推偏。

## 日志结论

### 12 号日志

路径：

```text
E:\53-all\gg-fc\04-f405-pavo20Pro\06-inav\02-log\12-还是打高下降
```

关键窗口：

```text
29.599060s -> 32.274418s
navFlags = 47
```

现象：

```text
surfaceRaw: 51 -> 22 cm
navPos[2]: 57 -> 28 cm
真实平均垂向速度: 约 -10.8 cm/s
navVel[2] 平均: 约 +31.1 cm/s
debug[3] / aglVel 平均: 约 +31.1 cm/s
debug[6] / est.vel.z 平均: 约 +147.4 cm/s
```

结论：

```text
ToF / AGL 高度显示飞机在下降，但速度估计认为飞机在上升。
```

### 13 号日志

路径：

```text
E:\53-all\gg-fc\04-f405-pavo20Pro\06-inav\02-log\13-排查加速度的问题
```

参数：

```text
acc_lpf_hz = 15
debug_mode = AGL
```

关键窗口：

```text
15.554s -> 17.527s
navFlags = 47
```

统计：

```text
surfaceRaw: 78 -> 24 cm
真实 surface 速度: 约 -27.6 cm/s
navVel[2] 平均: 约 +16.7 cm/s
navTgtVel[2] 平均: 约 +16.3 cm/s
navAcc[2] 平均: 约 +70.8 cm/s^2
navAcc[2] 范围: -219 -> +338 cm/s^2
accVib 平均: 约 3171
```

结论：

```text
飞手上推油门，目标速度确实变成向上，但 navVel[2] 也偏正。
速度环认为当前速度接近目标速度，因此不会强烈加油门。
```

### 14 号日志

路径：

```text
E:\53-all\gg-fc\04-f405-pavo20Pro\06-inav\02-log\14-发现加速度震动太大
```

参数变化：

```text
13 号: acc_lpf_hz = 15
14 号: acc_lpf_hz = 10
acc_notch_hz = 0
```

黑匣子 header 中没有 `acczero_x/y/z`、`accgain_x/y/z`、`align_board_*`，因此 14 号日志不能证明 IMU 校准参数变化，只能证明 LPF 变化。

14 号确认：

```text
debug[7] 与 navAcc[2] 完全一致。
```

说明 `DEBUG_SET(DEBUG_AGL, 7, posEstimator.imu.accelNEU.z)` 已经生效。

第一段刚进入定高：

```text
18.268s -> 18.998s
navFlags = 47
surfaceRaw: 96 -> 68 cm
真实 surface 速度: 约 -37.6 cm/s
navVel[2] 平均: 约 +2.8 cm/s
navTgtVel[2] 平均: 约 +5.7 cm/s
navAcc[2] / debug[7] 平均: 约 -21.1 cm/s^2
accVib 平均: 约 3035
```

和 13 号相比，这段有改善：

```text
acc_lpf_hz 从 15 降到 10 后，刚切入时 navAcc[2] 不再强烈偏正。
```

但后面进入 stick 调整：

```text
18.998s -> 19.387s
navFlags = 175
surfaceRaw: 68 -> 55 cm
真实 surface 速度: 约 -30.1 cm/s
navVel[2]: -17 -> +27 cm/s
navVel[2] 平均: 约 +12.2 cm/s
navAcc[2] / debug[7] 平均: 约 +252.9 cm/s^2
accVib 平均: 约 3754
rcCommand[3]: 1415 -> 1348
```

这段说明：

```text
ToF 仍然看到飞机下降，但导航垂向加速度出现强烈正值，把 navVel[2] 推成正值。
速度环认为飞机已经在上升，于是油门输出反而下降。
```

后面一段“推油门但仍下降”的典型窗口：

```text
27.500s -> 28.750s
navFlags = 175
surfaceRaw: 81 -> 59 cm
真实 surface 速度: 约 -22.3 cm/s
rcData[3]: 1560 -> 1574
navTgtVel[2] 平均: 约 +21.9 cm/s
navVel[2] 平均: 约 +20.0 cm/s
navAcc[2] / debug[7] 平均: 约 +85.6 cm/s^2
rcCommand[3] 平均: 约 1365.8
```

解释：

```text
飞手确实上推油门，navTgtVel[2] 也确实是向上的。
但 navVel[2] 反馈也接近 +20 cm/s。
速度环认为当前速度已经接近目标速度，所以不会继续明显加油门。
现实中 surfaceRaw 仍然下降，于是出现“推油门但飞机还在掉高”。
```

## 当前根因判断

目前最强证据指向：

```text
飞行中 IMU 垂向加速度 navAcc[2] / debug[7] 存在振动相关的低频偏置或校准/安装残差，
导致 AGL 速度估计偏正。
```

这个错误进入速度环后，会造成：

```text
真实高度下降 -> ToF 看到了下降
navVel[2] 却认为上升或接近目标上升速度
速度环不给足油门，甚至减小 rcCommand[3]
飞机继续下降
```

所以当前问题不是单纯的：

- 高度目标 `navTgtPos[2]` 跳变。
- stick 输入没有生效。
- ToF 高度完全错误。
- hover throttle 单独设置太低。

这些因素可能影响体感，但 12/13/14 号日志里的主矛盾是：

```text
AGL / nav 垂向速度反馈和 ToF 实际高度变化方向不一致。
```

## 参数判断

### `acc_lpf_hz`

`acc_lpf_hz = 15 -> 10` 有改善，但没有根治。

14 号中 `accVib` 仍然较高：

```text
切换前 10s -> 18.2s: accVib 平均约 3857，最大约 5293
第一段 navFlags=47: accVib 平均约 3035
第一段 navFlags=175: accVib 平均约 3754
长时间 navFlags=175: accVib 平均约 3406，最大约 4687
```

在 `acc_1G = 2048` 的情况下，`accVib = 3000~4000` 已经是很重的加速度振动估计。

建议：

```text
acc_lpf_hz = 10 先保留。
如果机械振动暂时无法处理，可以小步试 8 或 7，但要注意低通越低，响应延迟越大。
```

### `acc_notch_hz`

目前不建议盲目打开。

原因：

```text
已有频谱更像低频偏置 / 低频晃动问题，不是明确单一高频峰。
acc_notch 适合明确频点的窄带振动，不适合靠猜。
```

### `inav_w_z_surface_p`

可以适度提高，用来让 AGL 高度更贴 ToF。

但它不是根因修复，因为当前主矛盾在速度估计。

建议：

```text
如果默认是 3.5，可以小步试 5 左右。
```

### `inav_w_z_surface_v`

不建议继续大幅提高。

原因：

```text
之前把 surface velocity 修正权重加大后出现弹跳。
ToF 高度虽然可靠，但过大的速度修正会把 ToF 噪声、反射变化、姿态变化注入速度环。
```

建议：

```text
如果已经调到 10，可以先回到 5~6.1 附近。
```

### hover throttle

提高 hover throttle 可以改善切模式瞬间油门下掉导致的体感掉高，但它不能修复速度估计错误。

当前 13/14 号日志里更关键的是：

```text
速度环反馈 navVel[2] 错误，导致推油门时控制器认为速度已经够了。
```

## 下一步建议

### 1. 做完整加速度计校准

尤其是六面校准。

校准后导出：

```text
diff all
get acczero
get accgain
get align_board
```

原因：

```text
当前黑匣子没有这些参数，无法判断 acczero / accgain / board alignment 是否有问题。
```

### 2. 下一把用 `DEBUG_VIBE`

不需要改控制逻辑，现有代码已有输出：

```c
DEBUG_SET(DEBUG_VIBE, 4, posEstimator.imu.accWeightFactor * 1000);
DEBUG_SET(DEBUG_VIBE, 5, posEstimator.imu.accelBias.x);
DEBUG_SET(DEBUG_VIBE, 6, posEstimator.imu.accelBias.y);
DEBUG_SET(DEBUG_VIBE, 7, posEstimator.imu.accelBias.z);
```

切换：

```text
set debug_mode = VIBE
save
```

重点看：

- `debug[0..2]`: 分轴振动。
- `debug[4]`: `accWeightFactor * 1000`，判断导航估计器是否因为振动降低加速度权重。
- `debug[7]`: `accelBias.z`，判断 Z 轴 bias 是否在飞行中修回来。

黑匣子本身仍然有：

- `navAcc[2]`
- `navVel[2]`
- `navTgtVel[2]`
- `surfaceRaw`
- `navPos[2]`

所以即使不用 `DEBUG_AGL`，主线证据也不会丢。

### 3. 机械侧重点

优先检查：

- 桨叶是否有破损、变形、动平衡问题。
- 电机轴是否弯。
- 飞控安装是否太硬或被机架共振直接传入。
- ToF 与飞控安装位置是否会被气流、机身震动、姿态变化影响。
- 飞控板朝向和 `align_board_*` 是否严格一致。

## 当前一句话结论

当前最可能的根因不是目标高度计算错误，也不是 stick 油门没有进入控制器，而是：

```text
飞行中导航垂向加速度 navAcc[2] / debug[7] 被振动、校准或安装残差污染，持续把 AGL / nav 垂向速度估计推偏正。
速度环因此误判飞机已经在上升或接近目标上升速度，导致推油门时仍然不给足油门，飞机实际继续掉高。
```

