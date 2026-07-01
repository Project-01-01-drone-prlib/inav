# 光流定点切入后 SURFACE 掉高分析

## 背景

这份笔记对应一次光流定点飞行日志：

```text
E:\53-all\gg-fc\04-f405-pavo20Pro\06-inav\02-log\03-光流定点\blackbox_log_2026-06-25_234137.TXT_data.csv
```

现象是：

- 飞机先在自稳模式飞到一定高度。
- 随后切入导航定点相关状态，`navState` 先变成 `3`，再变成 `7`。
- 切入后飞机实际对地高度快速下降。
- `surfaceRaw` 从约 `75cm` 在短时间内下降到个位数，最低接近 `1cm`。

期望行为是：

- 自稳模式飞到一定高度后切入定点。
- 飞机不应该主动掉高。
- 切入时应该把当前高度作为保持高度。
- 油门杆不大幅偏离时，应保持当前高度；只有明显推/收油门时才调整高度。

## 日志中的关键证据

日志中 `navState` 只有三次状态变化：

```text
起始       navState = 0
约 12.899s navState = 3
约 12.980s navState = 7
```

其中稳定编号来自 `src/main/navigation/navigation_private.h`：

```text
3 = NAV_PERSISTENT_ID_ALTHOLD_IN_PROGRESS
7 = NAV_PERSISTENT_ID_POSHOLD_3D_IN_PROGRESS
```

切入附近的关键字段如下：

```text
相对时间    navState  navFlags  surfaceRaw  navPos[2]  navTgtPos[2]  rcData[3]  rcCommand[3]
12.851s    0         39        76          1024       0             1332      1333
12.902s    3         39        76          1023       1024          1334      1305
12.952s    3         39        75          1023       1024          1367      1291
13.003s    7         239       75          87         59            1370      1302
13.104s    7         239       73          84         59            1370      1273
13.307s    7         175       62          74         57            1353      1345
14.976s    7         239       7           21         78            1530      1343
15.683s    7         239       1           15         93            1628      1279
```

最关键的变化是：

```text
12.902s: navState = 3, navTgtPos[2] = 1024
13.003s: navState = 7, navTgtPos[2] = 59
```

这说明刚进入 `ALTHOLD` 时，高度目标仍接近当前高度；但进入 `POSHOLD_3D` 后，目标高度突然变成约 `59cm`。之后飞机开始向下追这个目标，`surfaceRaw` 从 `75cm` 快速下降。

## navFlags 的含义

`navFlags` 的写入位置在：

```text
src/main/navigation/navigation.c:4367
```

相关代码：

```c
navFlags = 0;
if (posControl.flags.estAltStatus == EST_TRUSTED)       navFlags |= (1 << 0);
if (posControl.flags.estAglStatus == EST_TRUSTED)       navFlags |= (1 << 1);
if (posControl.flags.estPosStatus == EST_TRUSTED)       navFlags |= (1 << 2);
if (posControl.flags.isTerrainFollowEnabled)            navFlags |= (1 << 3);
if (posControl.flags.estHeadingStatus == EST_TRUSTED)   navFlags |= (1 << 5);

if (posControl.flags.isAdjustingPosition)       navFlags |= (1 << 6);
if (posControl.flags.isAdjustingAltitude)       navFlags |= (1 << 7);
if (posControl.flags.isAdjustingHeading)        navFlags |= (1 << 8);
```

切入前：

```text
navFlags = 39
```

表示：

```text
bit0: 高度估计可信
bit1: AGL 估计可信
bit2: 位置估计可信
bit5: 航向估计可信
```

进入 `POSHOLD_3D` 后：

```text
navFlags = 239
```

相对 `39` 多出来的关键位是：

```text
bit3: isTerrainFollowEnabled
bit6: isAdjustingPosition
bit7: isAdjustingAltitude
```

因此，这次切入 `POSHOLD` 后并不是普通高度保持，而是启用了 `SURFACE / terrain follow` 分支。

## 根因

地形跟随是否启用由下面的函数决定：

```text
src/main/navigation/navigation.c:1274
```

```c
static bool navTerrainFollowingRequested(void)
{
    // Terrain following not supported on FIXED WING aircraft yet
    return !STATE(FIXED_WING_LEGACY) && IS_RC_MODE_ACTIVE(BOXSURFACE);
}
```

也就是说，多旋翼下只要 `BOXSURFACE` 模式打开，导航高度控制就会启用 `isTerrainFollowEnabled`。

进入 `ALTHOLD` 或 `POSHOLD_3D` 初始化时，会调用：

```text
src/main/navigation/navigation.c:1304
src/main/navigation/navigation.c:1334
```

```c
resetAltitudeController(navTerrainFollowingRequested());
setupAltitudeController();
setDesiredPosition(&navGetCurrentActualPositionAndVelocity()->pos, posControl.actualState.yaw, NAV_POS_UPDATE_Z);
```

`resetAltitudeController()` 内部会设置：

```text
src/main/navigation/navigation.c:3694
```

```c
posControl.flags.isTerrainFollowEnabled = useTerrainFollowing;
```

当 `isTerrainFollowEnabled` 为真时，`navGetCurrentActualPositionAndVelocity()` 返回的是 AGL 状态：

```text
src/main/navigation/navigation.c:2941
```

```c
return posControl.flags.isTerrainFollowEnabled ? &posControl.actualState.agl : &posControl.actualState.abs;
```

到这里为止，切入时用当前 AGL 作为 Z 目标是合理的。日志里 `navState = 3` 时 `navTgtPos[2] = 1024`，也说明当时目标还没有异常掉低。

真正导致目标高度被改低的是多旋翼 RC 高度输入分支：

```text
src/main/navigation/navigation_multicopter.c:122
```

修改前逻辑是：

```c
if (posControl.flags.isTerrainFollowEnabled) {
    const int16_t altTarget = scaleRange(rcCommand[THROTTLE],
                                         getThrottleIdleValue(),
                                         getMaxThrottle(),
                                         0,
                                         navConfig()->general.max_terrain_follow_altitude);

    if (posControl.flags.estAglStatus == EST_TRUSTED && altTarget > 10) {
        updateClimbRateToAltitudeController(0, altTarget, ROC_TO_ALT_TARGET);
    }
}
```

这段代码的实际含义是：

```text
SURFACE 模式下：
    当前 rcCommand[THROTTLE] 绝对值
        -> 直接映射成 0 到 nav_max_terrain_follow_alt 之间的 AGL 目标高度
```

默认 `nav_max_terrain_follow_alt` 是：

```text
src/main/fc/settings.yaml:2770
default_value: 100cm
```

因此，切入 `POSHOLD + SURFACE` 后，如果当时油门位置映射出来的 AGL 目标只有约 `59cm`，而飞机实际 `surfaceRaw` 在 `75cm`，控制器就会主动降低油门，让飞机下降去追这个目标。

这正是日志中发生的事情。

## 为什么这不是单纯的油门零点问题

普通 `ALTHOLD/POSHOLD` 下，INAV 会在进入高度控制时记录一个油门零点：

```text
src/main/navigation/navigation_multicopter.c:175
```

```c
if (throttleType == MC_ALT_HOLD_STICK && !throttleIsLow) {
    altHoldThrottleRCZero = rcCommand[THROTTLE];
} else if (throttleType == MC_ALT_HOLD_HOVER) {
    altHoldThrottleRCZero = currentBatteryProfile->nav.mc.hover_throttle;
} else {
    altHoldThrottleRCZero = rcLookupThrottleMid();
}
```

普通分支后续使用：

```c
rcCommand[THROTTLE] - altHoldThrottleRCZero
```

来产生爬升/下降速度请求。

但修改前的 `SURFACE / terrain follow` 分支绕过了这套油门零点模型，直接把油门绝对位置映射成 AGL 目标高度。于是用户期望的“切入定点时保持当前高度”与代码实现的“油门位置决定地形跟随目标高度”发生冲突。

## 修改策略

本次修改目标：

```text
在 SURFACE + POSHOLD/ALTHOLD 中，如果 AGL 可信：
    不再把油门绝对位置直接映射成目标 AGL 高度；
    改为复用普通定高的油门零点模型；
    切入时油门附近保持当前高度；
    油门明显高于/低于零点时，才产生爬升/下降速度请求。
```

修改后的 `isTerrainFollowEnabled && estAglStatus == EST_TRUSTED` 分支逻辑变成：

```c
const uint8_t deadband = rcControlsConfig()->alt_hold_deadband;
const int16_t rcThrottleAdjustment = applyDeadband(rcCommand[THROTTLE] - altHoldThrottleRCZero, deadband);

if (rcThrottleAdjustment) {
    int16_t controlRange = -deadband;
    controlRange += rcThrottleAdjustment > 0 ? getMaxThrottle() - altHoldThrottleRCZero : altHoldThrottleRCZero - getThrottleIdleValue();

    const int16_t rcClimbRate = rcThrottleAdjustment * navConfig()->mc.max_manual_climb_rate / controlRange;
    updateClimbRateToAltitudeController(rcClimbRate, 0, ROC_TO_ALT_CONSTANT);

    return true;
} else {
    if (posControl.flags.isAdjustingAltitude) {
        updateClimbRateToAltitudeController(0, 0, ROC_TO_ALT_CURRENT);
    }

    return false;
}
```

AGL 不可信时，保留原来的安全下降逻辑：

```c
updateClimbRateToAltitudeController(climbRate, 0, ROC_TO_ALT_CONSTANT);
```

## 修改后的预期行为

修改前：

```text
SURFACE + POSHOLD:
    油门绝对位置 -> AGL 目标高度
    切入时可能把目标高度从当前 75cm 改成 59cm
    飞机会主动掉高
```

修改后：

```text
SURFACE + POSHOLD:
    切入时记录当前油门零点
    切入时当前 AGL 高度作为保持目标
    油门在零点死区附近时保持当前高度
    油门高于零点时请求上升
    油门低于零点时请求下降
```

这更符合光流定点的直觉使用方式：

```text
自稳飞到合适高度 -> 切定点 -> 保持当前高度和位置
```

## 不改代码的规避方法

如果保持上游原始逻辑，不想改变固件行为，可以通过模式配置规避：

```text
切 POSHOLD 时不要同时打开 SURFACE
```

也就是：

```text
POSHOLD: 开
SURFACE: 关
```

这样会走普通定高逻辑，切入时不会把油门绝对位置映射成 AGL 目标高度。

如果希望光流定点时仍使用测距 AGL 控高，同时希望切入不掉高，则需要本次代码修改。

## 后续验证建议

下次飞行日志建议重点观察：

- `navState`
- `navFlags`
- `surfaceRaw`
- `navPos[2]`
- `navTgtPos[2]`
- `navVel[2]`
- `navTgtVel[2]`
- `rcData[3]`
- `rcCommand[3]`

验证目标：

```text
切入 POSHOLD_3D 后：
    navTgtPos[2] 不应突然从当前高度跳到较低目标；
    surfaceRaw 不应快速下降；
    油门不明显偏离切入零点时，navTgtVel[2] 应接近 0；
    明显推/收油门后，才出现对应的上升/下降目标速度。
```

