# AGL 高度滞后与加速度振动排查进展

## 背景

本笔记总结当前围绕 Pavo20 Pro / BETAFPVF405 的 INAV 高度控制问题的最新排查进展。

主要 log 来源：

```text
D:\40-bf\gg-board-fc\04-f405-pavo20Pro\06-inav\02-log\14-发现加速度震动太大
```

对应文件：

```text
inav_all.bbl
inav_all_data.csv
inav_all_param.csv
```

现象概括：

- 切入定高 / Surface / 光流定点后，飞机存在掉高。
- 部分区间里油门已经上推，`navTgtVel[2]` 方向也为向上，但飞机实际仍在下降。
- `surfaceRaw` 显示真实对地距离已经变小，例如约 `70 cm`，但 `navPos[2]` 仍认为 AGL 高度约 `82 cm`。
- `accVib` 长时间处于 `3000-4000` 区间，结合该 log 的 `acc_1G=2048`，相当于约 `1.5g-2.0g` 的加速度振动。

## 已确认的关键修正

### 1. `debug_mode=1` 是 `DEBUG_AGL`

当前代码中 `debugType_e` 的枚举顺序为：

```c
typedef enum {
    DEBUG_NONE,
    DEBUG_AGL,
    DEBUG_FLOW_RAW,
    ...
} debugType_e;
```

因此 log 参数：

```text
debug_mode,1
```

表示当前 log 已经开启 `DEBUG_AGL`，不是其他 debug 模式。

`DEBUG_AGL` 字段含义：

```text
debug[0] = surface.reliability * 1000
debug[1] = aglQual
debug[2] = aglAlt
debug[3] = aglVel
debug[4] = surface.alt
debug[5] = surface.alt - aglAlt
debug[6] = est.vel.z
debug[7] = accelNEU.z
```

对应代码位置：

```text
src/main/navigation/navigation_pos_estimator_agl.c
```

### 2. `navFlags=47` 时 `navPos[2]` 是 AGL 高度

`navFlags` 的低位含义来自：

```c
if (posControl.flags.estAltStatus == EST_TRUSTED)       navFlags |= (1 << 0);
if (posControl.flags.estAglStatus == EST_TRUSTED)       navFlags |= (1 << 1);
if (posControl.flags.estPosStatus == EST_TRUSTED)       navFlags |= (1 << 2);
if (posControl.flags.isTerrainFollowEnabled)            navFlags |= (1 << 3);
if (posControl.flags.estHeadingStatus == EST_TRUSTED)   navFlags |= (1 << 5);
```

所以：

```text
47 = 0b0010_1111
```

表示：

```text
bit0 = 高度估计可信
bit1 = AGL 估计可信
bit2 = 位置估计可信
bit3 = terrain follow / surface 模式启用
bit5 = 航向估计可信
```

当 `bit3` 置位时：

```c
return posControl.flags.isTerrainFollowEnabled
    ? &posControl.actualState.agl
    : &posControl.actualState.abs;
```

因此 `navFlags=47` 段落中：

```text
navPos[2] = posControl.actualState.agl.pos.z = posEstimator.est.aglAlt
```

不是 absolute altitude。

### 3. `posPID,"80,0,0"` 不是 Z 位置 P

Blackbox header 中：

```text
altPID = PID_POS_Z
posPID = PID_POS_XY
```

当前 log 参数：

```text
altPID,"50,0,0"
posPID,"80,0,0"
```

含义为：

```text
nav_mc_pos_z_p  = 50
nav_mc_pos_xy_p = 80
```

因此当前 Z 高度位置环 P 仍是 `50`，不是 `80`。

## 当前 log 中的关键证据

### AGL 残差不是因为测距质量低

红线附近典型数据：

```text
time      = 57378645 us
navFlags  = 47
surfaceRaw = 70
debug[4] surface.alt = 69
debug[2] aglAlt      = 81
navPos[2]            = 82
debug[5] residual    = -12
debug[0] reliability = 999
debug[1] aglQual     = 2
debug[3] aglVel      = -25
debug[6] global vel  = 72
debug[7] accelNEU.z  = 229
accVib               = 3705
```

`debug[1]=2` 对应：

```c
SURFACE_QUAL_HIGH
```

因此该段不是：

- rangefinder 不可信；
- AGL quality low；
- AGL quality mid 混合 baro/global altitude 后被拉偏。

它是在：

```text
surface reliability 满值
agl quality high
terrain follow enabled
```

的情况下，`aglAlt/navPos[2]` 仍高于 `surface.alt/surfaceRaw`。

### `surfaceRaw=70`、`navPos[2]=82` 的直接含义

该点实际对应的是：

```text
surfaceRaw          = 70
tilt-corrected alt  = debug[4] = 69
AGL fused estimate  = debug[2] = 81
Blackbox navPos[2]  = 82
residual            = debug[5] = -12
```

也就是：

```text
surface.alt - aglAlt = 69 - 81 = -12 cm
```

这不是单位错误，也不是 raw height 和 AGL height 混用了；它就是 AGL 估计器内部的融合残差。

### 姿态补偿不是主要原因

红线附近姿态很小：

```text
roll  ≈ -0.2 deg
pitch ≈ -0.7 deg
```

倾角补偿大致为：

```text
70 * cos(0.2 deg) * cos(0.7 deg) ≈ 69.99 cm
```

所以 `70 -> 82` 的差值不能由姿态补偿解释。

### AGL 估计滞后是明确存在的

红线附近连续数据：

```text
time       raw  surface.alt  aglAlt  navPos  residual  aglVel  accelNEU.z  accVib
57361923    78      77         82      82      -5       -27      193        3798
57378645    70      69         81      82     -12       -25      229        3705
57382823    70      69         80      80     -11       -25      238        3718
57403222    70      69         79      79     -10       -23      283        3657
57408362    68      67         78      79     -11       -22      294        3725
57423690    68      67         77      77     -10       -20      309        3850
```

可以看到：

- `surfaceRaw/surface.alt` 出现阶梯式下降；
- `aglAlt/navPos[2]` 没有立刻贴近测距高度；
- `debug[5]` 长时间为负值，说明融合 AGL 高度高于测距高度；
- 同时 `debug[7] accelNEU.z` 持续为正。

## 当前因果链判断

综合当前 log，最新判断为：

```text
1. rangefinder 被认为可信，AGL quality 为 HIGH；
2. 但 surface.alt 快速下降时，融合后的 aglAlt/navPos[2] 明显滞后；
3. 位置环使用滞后的 navPos[2] 作为实时高度；
4. 当前 nav_mc_pos_z_p = 50，Z 位置环 P 偏小；
5. 所以高度误差只转换成较小的 navTgtVel[2]；
6. 同时 accVib 约 1.5g-2.0g，Z 向 accelNEU.z 出现异常正值；
7. AGL 预测项和 surface residual 方向冲突，导致 AGL 估计更难快速贴近测距高度；
8. 速度环拿到的实际速度/加速度趋势被污染，油门修正不够果断；
9. 最终表现为油门上推或目标速度向上时，飞机仍会继续下降一段。
```

更简洁地说：

```text
位置环实时高度滞后 + Z 位置 P 偏小 + IMU Z 向振动/加速度估计异常
= 目标爬升速度偏小，速度环纠偏能力不足，掉高被放大。
```

## 当前最重要的嫌疑

### 1. IMU / 加速度 Z 向振动

该 log 中：

```text
acc_1G = 2048
accVib = 3000-4000
```

换算后约为：

```text
3000 / 2048 ≈ 1.46g
3700 / 2048 ≈ 1.81g
4000 / 2048 ≈ 1.95g
```

代码会用振动水平降低加速度权重：

```c
acc_vibration_factor = scaleRangef(
    constrainf(accGetVibrationLevel(), 1.0, 3.0),
    1.0, 3.0,
    1.0, 0.3
);
posEstimator.imu.accWeightFactor = acc_vibration_factor * acc_clip_factor;
```

当振动约 `1.8g-2.0g` 时，估算 `accWeightFactor` 大约会下降到 `0.65-0.72`。这说明当前加速度数据已经被估计器认为不够可靠，但它仍然会参与 AGL / altitude 预测。

当前 AGL log 中还出现了：

```text
surface.alt 快速下降
aglVel 仍在下降
accelNEU.z 却持续为正
```

这说明 Z 向加速度预测和 rangefinder residual 存在冲突。高 `accVib` 很可能是这个冲突的重要来源。

### 2. Z 位置环 P 偏小

红线附近：

```text
navTgtPos[2] = 103
navPos[2]    = 82
高度误差      = 21 cm
navTgtVel[2] = 11 cm/s
```

由于当前：

```text
nav_mc_pos_z_p = 50
实际 kP = 50 / 100 = 0.5
```

所以：

```text
21 cm * 0.5 = 10.5 cm/s
```

这与 `navTgtVel[2]=11` 完全吻合。

因此目标速度偏小不是偶然，它就是当前 Z 位置 P 的结果。

不过，当前不建议优先猛烈加 P。因为在 `accVib` 仍处于 `3000-4000` 的情况下，提高 P 可能会放大高度估计噪声和控制震荡。

## 下一步排查方向

### 第一优先：开启 `DEBUG_VIBE`

下一轮建议设置：

```text
set debug_mode = VIBE
save
```

`DEBUG_VIBE` 字段含义：

```text
debug[0] = X 轴 vibration * 100
debug[1] = Y 轴 vibration * 100
debug[2] = Z 轴 vibration * 100
debug[3] = acc clip count
debug[4] = accWeightFactor * 1000
debug[5] = accelBias.x
debug[6] = accelBias.y
debug[7] = accelBias.z
```

需要重点确认：

- 是否 `debug[2]`，也就是 Z 轴振动明显高于 X/Y；
- `debug[3]` 是否持续增加，若增加则说明发生 accelerometer clipping；
- `debug[4]` 是否经常低于 `800`，甚至低于 `700`；
- `debug[7] accelBias.z` 是否存在明显漂移；
- `accVib` 是否仍处于 `3000-4000`；
- 修复振动后，回到 `DEBUG_AGL` 时 `debug[5]` 是否从 `-10 cm` 级别收敛到更小。

初步判断标准：

```text
accVib < 2048       较理想，低于 1g vibration
accVib 2048-3000    偏高但可继续分析
accVib 3000-4000    明显过大，会影响高度估计
accVib > 4000       很不健康，应优先机械处理
```

`debug[4] = accWeightFactor * 1000` 判断：

```text
900-1000  较好
700-900   已明显降权
<700      高度/速度估计会明显受影响
```

`debug[3] acc clip count` 判断：

```text
不应持续增加。
如果持续增加，不应优先调 PID，应先处理机械振动、飞控安装、桨叶和电机。
```

### 第二优先：必要时开启 `DEBUG_ACC`

`DEBUG_ACC` 输出更底层的原始三轴加速度 ADC：

```c
DEBUG_SET(DEBUG_ACC, axis, accADC[axis]);
```

它适合用于确认：

- 原始 Z 轴加速度波形是否存在尖峰；
- 三轴中是否 Z 轴最异常；
- 是否存在明显机械共振频段；
- 原始加速度是否比滤波后或融合后数据更糟。

但 `DEBUG_ACC` 不直接给出：

- accWeightFactor；
- acc clip count；
- per-axis vibration level；
- accel bias。

因此当前建议顺序是：

```text
1. 先 DEBUG_VIBE
2. 如果需要看原始波形，再 DEBUG_ACC
3. 机械修复后，再 DEBUG_AGL 验证 residual 是否改善
```

### 第三优先：机械振动治理

优先检查：

- 飞控安装是否过硬，是否存在硬接触机架；
- 飞控固定胶、减震结构、螺丝是否过紧或松动；
- 排线、焊线是否拉扯飞控；
- 桨叶是否损伤或不平衡；
- 电机轴是否弯、电机轴承是否异常；
- 机架是否有松动或局部共振；
- 小机架 / duct / 保护圈是否引入高频振动。

不建议一开始只靠滤波掩盖机械振动。滤波可以辅助，但如果 `accVib` 长时间在 `3000-4000`，应先处理机械源头。

### 第四优先：振动改善后再调 Z 位置 P

振动改善后，如果仍感觉高度响应慢，可以逐步提高：

```text
set nav_mc_pos_z_p = 60
save
```

再根据 log 尝试：

```text
65
70
```

调参依据：

```text
如果高度误差明显，但 navTgtVel[2] 仍然很小，说明 Z 位置 P 仍偏保守。
如果 navTgtVel[2] 已经足够大，但 navVel[2] 跟不上，则应继续看速度环、油门动态或估计器。
```

当前不建议在振动未解决前大幅提高 `nav_mc_pos_z_p`，否则可能把估计噪声和控制输出一起放大。

## 当前结论

截至目前，排查结论为：

```text
1. 该 log 已经是 DEBUG_AGL。
2. navFlags=47 时 navPos[2] 确实是 AGL 高度。
3. surfaceRaw=70 而 navPos[2]=82，对应 AGL residual 约 -12 cm。
4. residual 出现在 reliability=999、aglQual=HIGH 的情况下，不是测距质量低导致。
5. 姿态补偿无法解释该差值。
6. AGL 估计存在明确滞后，且与异常的 accelNEU.z 正加速度预测冲突有关。
7. accVib 处于 1.5g-2.0g，明显过大，已足以影响高度/速度估计。
8. Z 位置环 P=50 偏小，使高度误差只产生较小 navTgtVel[2]。
9. 下一步应优先用 DEBUG_VIBE 定位具体振动轴、clip、accWeightFactor 和 bias。
10. 主修方向应先处理 IMU/加速度振动，再回头优化 nav_mc_pos_z_p。
```

一句话总结：

```text
当前问题不是单一 PID 参数问题，而是 AGL 高度估计滞后、Z 向加速度振动异常、Z 位置 P 偏小共同作用。
优先排查和修复 IMU / Z 向振动，再进行 Z 高度位置环增益优化。
```
