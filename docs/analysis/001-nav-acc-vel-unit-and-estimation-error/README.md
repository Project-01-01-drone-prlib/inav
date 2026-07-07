# NavAcc/NavVel Unit and Vertical Estimation Error Analysis

## Scope

This note analyzes the vertical estimator values in this log:

```text
D:\40-bf\gg-board-fc\04-f405-pavo20Pro\06-inav\02-log\17-*\inav_all_data.csv
```

The focus is the moment shortly after entering altitude hold where `surfaceRaw` indicates the aircraft is getting closer to the ground, while `navVel[2]` is still positive.

## Unit Confirmation

`navAcc[2]` is vertical acceleration in the navigation NEU frame:

```text
unit: cm/s^2
sign: positive is Up
```

`navVel[2]` is vertical velocity in the same NEU frame:

```text
unit: cm/s
sign: positive is Up
```

`surfaceRaw` is the raw rangefinder distance:

```text
unit: cm
meaning: measured distance to the surface
```

Therefore, if `surfaceRaw` is decreasing, the aircraft is moving closer to the surface. In the usual level-flight case over the floor, this means the aircraft is descending.

## Code Path

The acceleration starts as filtered accelerometer data in `g`, then is converted to `cm/s^2`:

```c
void accGetMeasuredAcceleration(fpVector3_t *measuredAcc)
{
    arm_scale_f32(acc.accADCf, GRAVITY_CMSS, measuredAcc->v, XYZ_AXIS_COUNT);
}
```

Source:

```text
src/main/sensors/acceleration.c
```

The IMU stores this as body-frame acceleration:

```c
accGetMeasuredAcceleration(&imuMeasuredAccelBF);  // Calculate accel in body frame in cm/s/s
```

Source:

```text
src/main/flight/imu.c
```

The position estimator rotates this body-frame acceleration into NEU, applies bias, subtracts gravity on Z, and exports it to `navAccNEU`:

```c
imuTransformVectorBodyToEarth(&accelReading);

posEstimator.imu.accelNEU.x = accelReading.x + posEstimator.imu.accelBias.x;
posEstimator.imu.accelNEU.y = accelReading.y + posEstimator.imu.accelBias.y;
posEstimator.imu.accelNEU.z = accelReading.z + posEstimator.imu.accelBias.z;

posEstimator.imu.accelNEU.z -= posEstimator.imu.calibratedGravityCMSS;

navAccNEU[X] = posEstimator.imu.accelNEU.x;
navAccNEU[Y] = posEstimator.imu.accelNEU.y;
navAccNEU[Z] = posEstimator.imu.accelNEU.z;
```

Source:

```text
src/main/navigation/navigation_pos_estimator.c
```

The vertical velocity estimate is integrated from this acceleration during prediction:

```c
posEstimator.est.vel.z += posEstimator.imu.accelNEU.z * ctx->dt;
```

Source:

```text
src/main/navigation/navigation_pos_estimator.c
```

Blackbox exports these values as:

```text
navVel[2] = navActualVelocity[Z]
navAcc[2] = navAccNEU[Z]
```

## Cursor Point From Screenshot

The screenshot cursor corresponds to the nearest CSV sample:

```text
time:        31.385016 s
navState:    3
navFlags:    47
surfaceRaw:  111 cm
navVel[2]:   +45 cm/s
navTgtVel[2]: -1 cm/s
navAcc[2]:   +130 cm/s^2
rcCommand[3]: 1344 us
accSmooth[2]: 2353 counts = 1.149 g  (acc_1G = 2048)
accVib:       9307 counts = 4.54 g
```

At this exact sample, the estimator says:

```text
vertical velocity:     +45 cm/s upward
vertical acceleration: +130 cm/s^2 upward
```

This is already suspicious because the rangefinder height is not increasing in the following interval. It starts dropping soon after.

## Full Alt-Hold Interval

Altitude hold was active over this interval:

```text
start:    31.241267 s
end:      33.388331 s
duration: 2.147064 s
navState: 3
navFlags: 47
```

Rangefinder:

```text
surfaceRaw start: 113 cm
surfaceRaw end:    16 cm
delta:            -97 cm
linear-fit slope: -64.22 cm/s
simple slope:     -45.18 cm/s
```

So from the rangefinder perspective, the aircraft was moving closer to the floor. The linear-fit estimate is about:

```text
actual vertical motion from surfaceRaw: about -64.2 cm/s
```

But the estimator reported:

```text
navVel[2] mean:   +10.44 cm/s
navVel[2] median:  +9.00 cm/s
navVel[2] range:  -18 to +46 cm/s
```

That means the signs disagree:

```text
surfaceRaw-derived motion: descending, about -64.2 cm/s
navVel[2] estimate:        upward, about +10.4 cm/s
```

The mean velocity disagreement is approximately:

```text
10.44 - (-64.22) = 74.66 cm/s
```

So the estimator is wrong by about:

```text
0.75 m/s
```

and, more importantly, it has the wrong sign.

## Cursor-To-End Window

From the screenshot cursor to the end of the alt-hold interval:

```text
start:    31.385016 s
end:      33.388331 s
duration: 2.003315 s
```

Rangefinder:

```text
surfaceRaw start: 111 cm
surfaceRaw end:    16 cm
delta:            -95 cm
linear-fit slope: -69.22 cm/s
```

Estimator:

```text
navVel[2] mean:   +8.15 cm/s
navVel[2] median: +5.00 cm/s
navVel[2] range:  -18 to +46 cm/s

navAcc[2] mean:   +88.59 cm/s^2
navAcc[2] median:  +4.00 cm/s^2
navAcc[2] range: -129 to +2104 cm/s^2
```

The velocity estimate error against `surfaceRaw` slope is:

```text
8.15 - (-69.22) = 77.37 cm/s
```

So in this two-second window, the estimator is about:

```text
0.77 m/s wrong
```

and still biased in the upward direction while the rangefinder indicates descent.

## First One Second After Cursor

From `31.385016 s` to `32.384068 s`:

```text
duration: 0.999052 s
surfaceRaw: 111 cm -> 73 cm
delta: -38 cm
linear-fit slope: -38.46 cm/s
```

Estimator:

```text
navVel[2] mean:   +16.81 cm/s
navVel[2] median: +17.00 cm/s

navAcc[2] mean:   -52.22 cm/s^2
navAcc[2] median: -67.00 cm/s^2
```

This one-second sub-window shows an important detail: after the cursor, `navAcc[2]` does go negative for a while. However, the velocity estimate is still positive on average:

```text
surfaceRaw-derived motion: about -38.5 cm/s
navVel[2] estimate:        about +16.8 cm/s
```

The velocity estimate error is:

```text
16.81 - (-38.46) = 55.27 cm/s
```

So even when `navAcc[2]` starts correcting downward, the velocity estimate remains too high and still has the wrong sign for this interval.

## Acceleration Magnitude

At the cursor:

```text
navAcc[2] = +130 cm/s^2
```

This is:

```text
130 cm/s^2 = 1.30 m/s^2
130 / 980.665 = 0.133 g
```

Across the full alt-hold interval:

```text
navAcc[2] mean:   +93.19 cm/s^2 = +0.95 m/s^2 = +0.095 g
navAcc[2] median: +24.00 cm/s^2 = +0.24 m/s^2 = +0.024 g
navAcc[2] max:   +2104 cm/s^2  = +21.04 m/s^2 = +2.15 g
```

The mean upward acceleration bias is large enough to materially corrupt vertical velocity. For example:

```text
+93 cm/s^2 held for 1 second -> +93 cm/s velocity error
+93 cm/s^2 held for 2 seconds -> +186 cm/s velocity error
```

Even a much smaller persistent bias, such as `+50 cm/s^2`, would create `+100 cm/s` velocity error in 2 seconds.

## Vibration Context

The same full alt-hold interval has:

```text
accVib median: 6451 counts = 3.15 g
accVib p95:   10523 counts = 5.14 g
accVib min:    3423 counts = 1.67 g
accVib max:   11602 counts = 5.67 g
```

At the cursor:

```text
accVib = 9307 counts = 4.54 g
```

This is a very high vibration level. It supports the hypothesis that the vertical acceleration estimate is still contaminated by dynamic vibration or vibration-induced bias.

## Control Output Was Not the Main Problem in This Log

The new conservative vertical PID settings prevented violent throttle swings:

```text
rcCommand[3] range in alt-hold: 1308 to 1380 us
mcVelAxisOut[2] range:          -73 to 0
mcVelAxisD[2]:                  0 throughout
```

So the controller was no longer producing the previous `1080 -> 1800` type throttle spike. The remaining issue is estimator quality:

```text
surfaceRaw indicates descent
navVel[2] remains positive or near zero
navAcc[2] has upward bias and large spikes
```

## Conclusion

The units are:

```text
navVel[2]: cm/s, positive Up
navAcc[2]: cm/s^2, positive Up
surfaceRaw: cm, raw distance to surface
```

At the screenshot cursor:

```text
surfaceRaw = 111 cm
navVel[2] = +45 cm/s
navAcc[2] = +130 cm/s^2
```

After that point, `surfaceRaw` falls from `111 cm` to `16 cm` in about `2.0 s`, with a fitted descent rate of approximately `-69.2 cm/s`. During the same window, `navVel[2]` averages `+8.15 cm/s`.

The vertical velocity estimate is therefore wrong by about:

```text
77 cm/s = 0.77 m/s
```

and its sign is opposite to the rangefinder-derived motion. This is a severe estimator error for altitude hold. The main remaining evidence points to contaminated vertical acceleration estimation under high vibration:

```text
accVib median during alt-hold: 3.15 g
navAcc[2] mean during alt-hold: +93.2 cm/s^2
accSmooth[2] mean during alt-hold: 2282.8 counts = 1.115 g
```

The safer PID settings prevented the controller from amplifying this into a throttle spike, but the estimator is still not trustworthy enough for aggressive altitude hold.
