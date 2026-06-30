# 光流定点下油门与高度行为分析

## 背景

这份笔记对应一次光流定点测试中的现象：

- `rcData[3]` 大约在 `1800`
- 飞机高度却相对稳定
- 直觉预期是“油门高于中位后，目标高度应该持续累加，飞机应该持续上升”

下面把这个现象和 INAV 多旋翼导航代码路径对应起来。

## 简短结论

在 `POSHOLD` 或 `ALTHOLD` 下，INAV **并不是**简单按“油门大于 1500 就一直往上加高度目标”来实现的。

它的垂直控制逻辑更接近下面这套模型：

1. 进入定高时，先确定一个油门“零点”。
2. 后续油门杆量会被解释成“相对于这个零点的爬升/下降速度指令”。
3. 当油门回到这个零点附近时，INAV 会停止继续爬升，并把**当前高度**锁成新的目标高度。
4. 导航模式真正使用的也不是原始 `rcData[3]`，而是处理过、并且后续还会被导航层覆盖的 `rcCommand[THROTTLE]`。

所以完全可能出现下面这种组合：

- `rcData[3]` 看起来很高
- `rcCommand[3]` 最后落在接近悬停油门的位置
- 高度保持稳定，而不是继续上升

## 最关键的区分

这里最重要的是先把两个量分开：

- `rcData[3]`：接收机原始输入
- `rcCommand[3]`：飞控内部真正参与控制的油门命令

基础油门命令入口在：

- `src/main/fc/fc_core.c:433`
- `src/main/fc/rc_controls.c:134`

相关代码：

```c
// src/main/fc/fc_core.c
rcCommand[THROTTLE] = throttleStickMixedValue();
```

```c
// src/main/fc/rc_controls.c
throttleValue = constrain(rxGetChannelValue(THROTTLE), lowLimit, PWM_RANGE_MAX);
throttleValue = (uint16_t)(throttleValue - lowLimit) * PWM_RANGE_MIN / (PWM_RANGE_MAX - lowLimit);
return rcLookupThrottle(throttleValue);
```

这意味着 `rcCommand[3]` 一开始就不是 `rcData[3]` 的原样拷贝，它会先经过油门曲线处理。

这段油门曲线在 `src/main/fc/rc_curves.c:39-69` 中生成，`rcMid` 和 `rcExpo` 都会影响映射结果。

## 进入 POSHOLD 或 ALTHOLD 时发生了什么

导航进入带高度控制的状态时，会先初始化高度控制器，并把当前高度设置为目标高度：

- `src/main/navigation/navigation.c:1302-1306`
- `src/main/navigation/navigation.c:1332-1336`

随后在下面这段逻辑里确定油门零点：

- `src/main/navigation/navigation.c:3707-3714`
- `src/main/navigation/navigation_multicopter.c:175-193`

核心代码如下：

```c
if (throttleType == MC_ALT_HOLD_STICK && !throttleIsLow) {
    altHoldThrottleRCZero = rcCommand[THROTTLE];
} else if (throttleType == MC_ALT_HOLD_HOVER) {
    altHoldThrottleRCZero = currentBatteryProfile->nav.mc.hover_throttle;
} else {
    altHoldThrottleRCZero = rcLookupThrottleMid();
}
```

这里就是你当前理解和 INAV 实际实现最容易错位的地方。

## 为什么“高于中位就持续上升”不是默认模型

配置项 `nav_mc_althold_throttle` 的默认值是 `STICK`，定义在：

- `src/main/fc/settings.yaml:2569-2573`

它的含义是：

- 进入定高模式的那一刻，飞控会把“当时的油门位置”记成零点
- 这个零点**不一定是 1500**
- 这个零点也**不一定是 hover throttle**

所以如果飞机是在一个比较高的油门位置进入 `POSHOLD`，那么那个较高的 `rcCommand[THROTTLE]` 就会被记录成后续高度调节的参考零点。

在这种情况下：

- 后面继续把杆量维持在差不多的位置，并不等于“继续上升”
- 而是更接近“保持零爬升率”

## 油门是如何变成爬升率指令的

RC 对高度的调节逻辑在：

- `src/main/navigation/navigation_multicopter.c:122-172`

核心计算是：

```c
const int16_t rcThrottleAdjustment =
    applyDeadband(rcCommand[THROTTLE] - altHoldThrottleRCZero, deadband);

if (rcThrottleAdjustment) {
    const int16_t rcClimbRate =
        rcThrottleAdjustment * navConfig()->mc.max_manual_climb_rate / controlRange;
    updateClimbRateToAltitudeController(rcClimbRate, 0, ROC_TO_ALT_CONSTANT);
} else {
    if (posControl.flags.isAdjustingAltitude) {
        updateClimbRateToAltitudeController(0, 0, ROC_TO_ALT_CURRENT);
    }
}
```

这段逻辑的含义是：

- 高于零点，产生上升速度请求
- 低于零点，产生下降速度请求
- 落在死区里，爬升速度请求为 0

所以它看的不是“是否高于 1500”，而是“是否偏离了 `altHoldThrottleRCZero`”。

## 为什么高度会停止上升

“停止爬升并把当前位置锁住”的行为来自 `ROC_TO_ALT_CURRENT`，代码在：

- `src/main/navigation/navigation.c:3656-3692`

关键部分如下：

```c
if (mode == ROC_TO_ALT_CURRENT) {
    posControl.desiredState.pos.z = navGetCurrentActualPositionAndVelocity()->pos.z;
    desiredClimbRate = 0.0f;
}
```

这段非常关键。

当油门杆回到零点附近时，INAV 不会继续累加目标高度，而是直接把**当前高度**写回 `desiredState.pos.z`，同时把爬升需求改成 0。

所以飞机前面即便上升过，只要后面回到了这个中性区间，高度就会稳定下来。

## 为什么原始油门很高，但导航实际油门却不高

在多旋翼定高控制中，导航最终会围绕悬停油门加一个 PID 修正来生成油门输出：

- `src/main/navigation/navigation_multicopter.c:108-120`

核心逻辑：

```c
int16_t rcThrottleCorrection = ...;
posControl.rcAdjustment[THROTTLE] =
    setDesiredThrottle(currentBatteryProfile->nav.mc.hover_throttle + rcThrottleCorrection, false);
```

然后导航层会直接覆盖当前生效的油门命令：

- `src/main/navigation/navigation_multicopter.c:273-277`

```c
rcCommand[THROTTLE] = posControl.rcAdjustment[THROTTLE];
rcCommandAdjustedThrottle = rcCommand[THROTTLE];
```

也就是说，在导航定高模式里：

- 飞手输入只是表达“想上升、想下降、还是想保持”
- 导航层把这个意图转成爬升率或高度目标
- 再由高度控制器围绕 `hover_throttle` 计算出真正的输出油门
- 最终的 `rcCommand[THROTTLE]` 完全可能远低于原始 `rcData[3]`

这正好能解释你截图里的现象：原始输入大约 `1800`，而实际参与导航控制的油门只有大约 `1355`。

## 另一个需要排查的分支：最大高度限制

还有一个次要但值得排查的逻辑：

- `src/main/navigation/navigation.c:3680-3689`
- `src/main/fc/settings.yaml:2776-2780`

如果 `nav_max_altitude` 不为 0，INAV 会在各类导航模式下对目标高度做上限钳制，包含 `Altitude Hold`。

所以如果飞机最后稳定在某个“顶住上限”的高度附近，这个配置也可能参与了现象形成。

## 对这次飞行现象的更贴近代码的解释

基于代码路径，更可能的解释是：

1. 飞机是在一个已经偏高的油门位置进入了 `POSHOLD` 或 `ALTHOLD`。
2. 因为 `nav_mc_althold_throttle` 默认是 `STICK`，所以那一刻的 `rcCommand[THROTTLE]` 被记成了 `altHoldThrottleRCZero`。
3. 后面虽然你看到 `rcData[3]` 依然很高，但只要 `rcCommand[THROTTLE]` 相对这个零点没有继续明显偏高，INAV 就会把它理解为“接近零爬升率需求”。
4. 一旦进入死区附近，导航层就会把当前高度锁成新的保持高度，而不是继续往上累计。
5. 最后真正送给高度控制器的油门会回到“悬停油门加修正”的范围，而不是一直跟着原始 `rcData[3]` 走。

## 后续看实际日志时最应该核对什么

如果要在具体 Blackbox 或导出的日志里验证这件事，建议重点看下面这些量在 `POSHOLD/ALTHOLD` 切入前后的变化：

- 模式切换时刻
- `rcData[3]`
- `rcCommand[3]`
- 高度估计值
- 垂直速度或 climb rate
- `nav_max_altitude` 是否配置过
- `nav_mc_althold_throttle` 的实际值
- 油门曲线相关参数，比如 `thr_mid` 和 `thr_expo`

最关键的问题其实是：

- 进入定高的那个瞬间，`rcCommand[THROTTLE]` 到底是多少？

如果那个值本来就已经偏高，那么后面出现“看起来油门很高，但高度没有继续升”的行为，反而正是 INAV 当前实现下的合理结果。

## 最终结论

这次现象和 INAV 的实现是一致的，不适合再用“高于 1500 就应该持续累加高度目标”来理解。

更准确的理解方式应该是：

- 定高模式会先确定一个可配置的油门零点
- 默认配置会记住进入模式那一刻的油门位置
- 后续只看相对这个零点的偏移量来决定爬升或下降
- 回到零点附近后，INAV 会把当前高度锁住
- 最终导航层会围绕悬停油门重新生成输出油门

所以这次更可能的根因不是“控制器忽略了你的油门”，而是“油门被按进入定高时记录下来的参考零点来解释”，而不是按固定中位绝对值来解释。
