/* =============================================================================
 *  The DOWN loiter autopilot's maths (runtime 0.28.5; tools/re/KILLS_HEALTH_DEATH.md 7). Pure: no game memory, no
 *  Windows, so tools/checks/flight_test.c flies it against model planes. Included by flight.c (and that test); needs
 *  memset / memcpy, Sin, Cos (survival_rt.c), CoAtan2, CoSqrt, CoAbs and CO_PI (coop.c).
 *
 *  Each step takes the plane's position (cm) and rotation (degrees: pitch, yaw, roll, UE's FRotator: nose up, nose
 *  right and right wing down are positive) and gives BuildFlightInput's pitch, yaw, roll, throttle and brake. It flies a
 *  circle of `radius` m round (cx, cy) at `alt` m: a heading wanted from where the plane is on the circle, a bank from
 *  the heading error, a climb angle from the altitude error, all clamped and slew-limited (gentle, never a high-G
 *  pull), throttle and brake 0 (AC8's neutral: cruise speed).
 *
 *  Which way a positive pitch or roll INPUT moves the plane isn't known from the code (SetInput 0x144d32580 negates all
 *  three axes into the flight engine's own frame), so the first time it runs it learns both: hands off until the plane
 *  is calm, roll +0.3, -0.3, -0.3, +0.3 for 0.25 s each, wings levelled, the same with pitch, comparing the mean body
 *  rates under + and under - (the order cancels a steady drift). The signs are kept for the next DOWN (DownInit's
 *  signsKnown). Round the circle, a slow integral of the radius error turns the heading wanted in or out until the
 *  plane holds the radius, whatever bank its flight model needs for it.
 *
 *  The probe can still read a sign wrong (a plane that answers late), so round the circle the body rates are checked
 *  against the inputs given (DnCheck): a plane that turns against them for DN_CHECK_W flips that sign. The user's co-op
 *  run of 2026-10-30 (runtime 0.28.6): the probe read -3 / +2 deg/s as a sign (DN_MIN_DIFF was 2, its quarters 0.25 s),
 *  the wrong roll sign held the host's DOWN plane upside down for 2.5 minutes, at 15 m over the sea, out of the combat
 *  zone, and the mission failed.
 * ============================================================================= */

#define DN_PROBE_IN    0.3     /* the sign probe's input                                                          */
#define DN_PROBE_S     0.5     /* each quarter of a probe (+, -, -, +), s                                          */
#define DN_PROBE_SKIP  0.25    /* the start of each quarter isn't measured (the response turning round, late), s  */
#define DN_SETTLE_S    1.5     /* longest hands-off wait for a calm plane before the probes, s                    */
#define DN_LEVEL_S     2.0     /* longest wings-level wait between the probes, s                                  */
#define DN_MIN_DIFF    10.0    /* deg/s: a probe's two halves closer than this tell nothing (the prior is kept)    */
#define DN_CHECK_MIN   0.1     /* the in-flight check: smaller inputs aren't counted                               */
#define DN_CHECK_W     1.0     /* the in-flight check: input x seconds counted before a sign is judged             */
#define DN_CHECK_RATE  4.0     /* deg/s: the mean body rate along the inputs that confirms a sign (against: flips) */
#define DN_FLIPS_MAX   6       /* sign flips at most in one DOWN                                                   */
#define DN_CHECK_BANK  90.0    /* deg: the pitch check counts only under this bank                                 */
#define DN_DIVE_DEG    -40.0   /* the dive backstop: a descent steeper than this ...                                */
#define DN_DIVE_S      10.0    /* ... this long, with the climb wanted 20 deg above it, flips the pitch sign       */
#define DN_BANK_MAX    40.0    /* deg                                                                              */
#define DN_SLEW        3.0     /* input units a second (outside the probes)                                        */
#define DN_GAP_S       0.5     /* longer between two samples (a pause, a load): start the rates over               */
#define DN_SAME_S      0.008   /* closer than this: the same frame (BuildFlightInput runs 2-3 times a frame)       */

enum { DN_START, DN_SETTLE, DN_ROLL, DN_LEVEL, DN_PITCH, DN_CIRCLE };
#define DN_LEARNED_ROLL   1    /* DownCtl.learned: the roll probe ended with a sign                                */
#define DN_LEARNED_PITCH  2
#define DN_VAGUE_ROLL     4    /* a probe that told nothing (the prior +1 kept)                                    */
#define DN_VAGUE_PITCH    8
#define DN_FLIPPED_ROLL  16    /* the in-flight check: the plane turned against the inputs, the sign flipped       */
#define DN_FLIPPED_PITCH 32
#define DN_CONFIRMED_ROLL  64  /* the in-flight check: the plane turned along the inputs                           */
#define DN_CONFIRMED_PITCH 128
#define DN_FLIPPED_DIVE  256   /* the dive backstop flipped the pitch sign                                         */

typedef struct {
    double cx, cy, alt, radius;              /* the circle: centre in cm, altitude and radius in m                  */
    int    sRoll, sPitch, signsKnown;        /* input signs: +1 = a positive input rolls right / raises the nose    */
    int    phase, dir;                       /* dir +1 a right-hand circle, -1 a left-hand one                       */
    double phaseAt, calmAt;                  /* when the phase (a probe: its quarter) began; since when it's calm   */
    int    sub;                              /* a probe's quarter: 0 +, 1 -, 2 -, 3 +                                 */
    double acc[2], accW[2];                  /* a probe's + and - quarters: rate x dt summed, dt summed              */
    double probeRate[4];                     /* mean body rates (deg/s): roll +, roll -, pitch +, pitch -            */
    int    learned;                          /* DN_LEARNED_* / DN_VAGUE_* bits, cleared by the caller once logged   */
    int    have; double t, p[3], r[3];       /* the last sample                                                       */
    int    haveRates; double v[3], rp, rq, rth;   /* smoothed velocity (cm/s), body roll rate, body pitch rate, Euler
                                                     pitch rate (deg/s)                                               */
    double altI;                             /* the altitude error integral, m s                                      */
    double radI;                             /* the radius error integral, deg of heading (turned in when positive)  */
    double bankI;                            /* the bank error integral, roll input                                   */
    double oP, oR;                           /* the inputs last given (raw: what BuildFlightInput's out gets)         */
    double lastBank;                         /* the bank last asked for (its side kept through ~180 deg errors)      */
    double chk[4];                           /* the in-flight check: roll rate x input and |input| x dt summed; pitch */
    double resp[2];                          /* the last check's mean body rate along the inputs (deg/s): roll, pitch */
    int    flips;                            /* signs flipped by the check (and the dive backstop)                   */
    double diveAt;                           /* since when the plane dives steeper than DN_DIVE_DEG wanting to climb */
    float  out[5];
    double dist, headErr, bankWant, gamma;   /* for the log                                                           */
} DownCtl;

static double DnWrap(double a) { while (a > 180.0) a -= 360.0; while (a < -180.0) a += 360.0; return a; }
static double DnClamp(double v, double lo, double hi) { return v < lo ? lo : v > hi ? hi : v; }
static double DnSlew(double cur, double want, double step)
{
    if (want > cur + step) return cur + step;
    if (want < cur - step) return cur - step;
    return want;
}

static void DownInit(DownCtl* c, double cx, double cy, double alt, double radius, int signsKnown, int sRoll, int sPitch)
{
    memset(c, 0, sizeof(*c));
    c->cx = cx; c->cy = cy; c->alt = alt; c->radius = radius;
    c->signsKnown = signsKnown;
    c->sRoll = sRoll < 0 ? -1 : 1;
    c->sPitch = sPitch < 0 ? -1 : 1;
    c->phase = DN_START;
    c->dir = 1;
}

/* The way round that needs the smaller turn from the plane's track (deg); right-hand near the centre. */
static void DnPickDir(DownCtl* c, const double* pos, double track)
{
    double x = (pos[0] - c->cx) / 100.0, y = (pos[1] - c->cy) / 100.0;
    if (CoSqrt(x * x + y * y) < 0.2 * c->radius) { c->dir = 1; return; }
    double beta = CoAtan2(y, x) * 180.0 / CO_PI;
    c->dir = CoAbs(DnWrap(beta + 90.0 - track)) <= CoAbs(DnWrap(beta - 90.0 - track)) ? 1 : -1;
}

/* Wings level (UE sense: a positive result rolls right). */
static double DnLevel(const DownCtl* c, double bank) { return DnClamp(0.025 * (0.0 - bank) - 0.005 * c->rp, -0.5, 0.5); }

/* The in-flight sign check on one axis (0 roll, 1 pitch): u the input given over the last dt in UE's sense (through the
 * sign believed), rate the body rate measured. Once DN_CHECK_W of input is counted: a mean rate along the inputs
 * confirms the sign, against them flips it (a wrong roll sign holds the plane upside down, a wrong pitch sign dives it). */
static void DnCheck(DownCtl* c, int axis, double u, double rate, double dt)
{
    if (CoAbs(u) < DN_CHECK_MIN) return;
    double* k = &c->chk[axis * 2];
    k[0] += u * rate * dt; k[1] += CoAbs(u) * dt;
    if (k[1] < DN_CHECK_W) return;
    double m = k[0] / k[1];
    c->resp[axis] = m;
    k[0] = k[1] = 0;
    if (m <= -DN_CHECK_RATE && c->flips < DN_FLIPS_MAX) {
        ++c->flips;
        if (axis) { c->sPitch = -c->sPitch; c->altI = 0; c->learned |= DN_FLIPPED_PITCH; }
        else { c->sRoll = -c->sRoll; c->bankI = 0; c->learned |= DN_FLIPPED_ROLL; }
    } else if (m >= DN_CHECK_RATE) c->learned |= axis ? DN_CONFIRMED_PITCH : DN_CONFIRMED_ROLL;
}

/* One step at time t (s). Writes out[0] pitch, [1] yaw, [2] roll, [3] throttle, [4] brake. Returns 1 when it computed
 * new inputs, 0 when it gave the last ones again (called again within the same frame). */
static int DownStep(DownCtl* c, double t, const double* pos, const double* rot, float* out)
{
    const double D2R = CO_PI / 180.0;
    if (!c->have || t - c->t > DN_GAP_S || t < c->t) {        /* the first sample, or after a pause: no rates over it */
        if (!c->have) {
            c->phase = c->signsKnown ? DN_CIRCLE : DN_SETTLE;
            if (c->phase == DN_CIRCLE) DnPickDir(c, pos, rot[1]);
        }
        c->phaseAt = t; c->calmAt = -1; c->sub = 0;            /* (a probe starts over) */
        c->acc[0] = c->acc[1] = c->accW[0] = c->accW[1] = 0;
        c->have = 1; c->t = t; memcpy(c->p, pos, 24); memcpy(c->r, rot, 24); c->haveRates = 0;
        memcpy(out, c->out, sizeof(c->out));
        return 1;
    }
    double dt = t - c->t;
    if (dt < DN_SAME_S) { memcpy(out, c->out, sizeof(c->out)); return 0; }

    /* measured: velocity, Euler rates, body rates (UE's FRotator is the aero convention: p = roll rate, q = pitch rate) */
    double vraw[3];
    for (int k = 0; k < 3; ++k) vraw[k] = (pos[k] - c->p[k]) / dt;
    double dth = DnWrap(rot[0] - c->r[0]) / dt, dps = DnWrap(rot[1] - c->r[1]) / dt, dph = DnWrap(rot[2] - c->r[2]) / dt;
    double th = rot[0] * D2R, ph = rot[2] * D2R;
    double q = dth * Cos(ph) + dps * Cos(th) * Sin(ph);
    double pr = dph - dps * Sin(th);
    if (!c->haveRates) {
        memcpy(c->v, vraw, 24); c->rp = pr; c->rq = q; c->rth = dth; c->haveRates = 1;
    } else {
        double a = DnClamp(dt / 0.1, 0.0, 1.0);
        for (int k = 0; k < 3; ++k) c->v[k] += (vraw[k] - c->v[k]) * a;
        c->rp += (pr - c->rp) * a; c->rq += (q - c->rq) * a; c->rth += (dth - c->rth) * a;
    }
    c->t = t; memcpy(c->p, pos, 24); memcpy(c->r, rot, 24);

    double bank = rot[2], age = t - c->phaseAt;
    double tR = 0, tP = 0;                                     /* the raw inputs wanted */
    int probing = 0;
    switch (c->phase) {
    case DN_SETTLE:                                            /* hands off until the plane is calm */
        if (CoAbs(c->rp) < 15.0 && CoAbs(c->rq) < 10.0) { if (c->calmAt < 0) c->calmAt = t; }
        else c->calmAt = -1;
        if ((c->calmAt >= 0 && t - c->calmAt >= 0.25) || age > DN_SETTLE_S) { c->phase = DN_ROLL; c->phaseAt = t; c->sub = 0; }
        break;
    case DN_ROLL: case DN_PITCH: {
        int roll = c->phase == DN_ROLL, minus = c->sub == 1 || c->sub == 2;
        probing = 1;
        if (roll) tR = minus ? -DN_PROBE_IN : DN_PROBE_IN;
        else { tR = c->sRoll * DnLevel(c, bank); tP = minus ? -DN_PROBE_IN : DN_PROBE_IN; }
        if (age >= DN_PROBE_SKIP) { c->acc[minus] += (roll ? pr : q) * dt; c->accW[minus] += dt; }
        if (age < DN_PROBE_S) break;
        c->phaseAt = t;
        if (++c->sub < 4) break;
        double mA = c->accW[0] > 0.1 ? c->acc[0] / c->accW[0] : 0, mB = c->accW[1] > 0.1 ? c->acc[1] / c->accW[1] : 0;
        int ok = c->accW[0] > 0.1 && c->accW[1] > 0.1 && CoAbs(mA - mB) >= DN_MIN_DIFF;
        c->probeRate[roll ? 0 : 2] = mA; c->probeRate[roll ? 1 : 3] = mB;
        if (roll) { if (ok) c->sRoll = mA > mB ? 1 : -1; c->learned |= ok ? DN_LEARNED_ROLL : DN_VAGUE_ROLL; }
        else      { if (ok) c->sPitch = mA > mB ? 1 : -1; c->learned |= ok ? DN_LEARNED_PITCH : DN_VAGUE_PITCH; }
        c->acc[0] = c->acc[1] = c->accW[0] = c->accW[1] = 0;
        c->sub = 0;
        if (roll) c->phase = DN_LEVEL;
        else {
            c->phase = DN_CIRCLE; c->signsKnown = 1;
            double vh = CoSqrt(c->v[0] * c->v[0] + c->v[1] * c->v[1]) / 100.0;
            DnPickDir(c, pos, vh > 20.0 ? CoAtan2(c->v[1], c->v[0]) / D2R : rot[1]);
        }
        break;
    }
    case DN_LEVEL:
        tR = c->sRoll * DnLevel(c, bank);
        if ((CoAbs(bank) < 12.0 && CoAbs(c->rp) < 25.0) || age > DN_LEVEL_S) { c->phase = DN_PITCH; c->phaseAt = t; c->sub = 0; }
        break;
    default: {                                                 /* DN_CIRCLE */
        DnCheck(c, 0, c->sRoll * c->oR, c->rp, dt);             /* (the inputs given over the last dt, the rates now) */
        if (CoAbs(bank) < DN_CHECK_BANK) DnCheck(c, 1, c->sPitch * c->oP, c->rq, dt);
        double x = (pos[0] - c->cx) / 100.0, y = (pos[1] - c->cy) / 100.0, h = pos[2] / 100.0;
        double rr = CoSqrt(x * x + y * y), R = c->radius;
        double vh = CoSqrt(c->v[0] * c->v[0] + c->v[1] * c->v[1]) / 100.0, vz = c->v[2] / 100.0;
        double track = vh > 20.0 ? CoAtan2(c->v[1], c->v[0]) / D2R : rot[1];
        /* the heading wanted: the circle's tangent, turned in (outside) or out (inside) by up to 80 / 45 deg, plus the
         * slow integral of the radius error near the circle (the turn the plane needs to hold it) */
        if (CoAbs(rr - R) < 0.5 * R) c->radI = DnClamp(c->radI + 4.0 * (rr - R) / R * dt, -30.0, 45.0);
        double delta = DnClamp(90.0 * (rr - R) / R + c->radI, -45.0, 80.0);
        double want = rr < 1.0 ? track : CoAtan2(y, x) / D2R + c->dir * (90.0 + delta);
        double e = DnWrap(want - track);
        double bankWant = 0.9 * e;
        if (CoAbs(e) > 150.0 && c->lastBank != 0.0) bankWant = c->lastBank > 0 ? DN_BANK_MAX : -DN_BANK_MAX;
        double bmax = (h < c->alt - 600.0 || h < 400.0) ? 25.0 : DN_BANK_MAX;   /* low: shallower turns */
        bankWant = DnClamp(bankWant, -bmax, bmax);
        c->lastBank = bankWant;
        /* the climb angle wanted from the altitude error (and its integral, slowly: the sag in a banked turn) */
        double eh = c->alt - h;
        c->altI = DnClamp(c->altI + eh * dt, -3000.0, 3000.0);
        double gammaWant = DnClamp(0.04 * eh + 0.0015 * c->altI, -12.0, 15.0);
        double vt = CoSqrt(vh * vh + vz * vz);
        double gamma = vt > 20.0 ? CoAtan2(vz, vh) / D2R : rot[0];
        /* the dive backstop: a steep dive the climb wanted doesn't pull it out of (a wrong pitch sign the check can't see
         * once the plane is near vertical) */
        if (gamma < DN_DIVE_DEG && gammaWant > gamma + 20.0) {
            if (c->diveAt <= 0) c->diveAt = t;
            else if (t - c->diveAt >= DN_DIVE_S && c->flips < DN_FLIPS_MAX) {
                ++c->flips; c->sPitch = -c->sPitch; c->altI = 0; c->diveAt = 0;
                c->learned |= DN_FLIPPED_PITCH | DN_FLIPPED_DIVE;
            }
        } else c->diveAt = 0;
        /* (the bank error's integral: a flight model whose roll input asks for a bank angle, not a roll rate, stops
         * short of the bank wanted without it) */
        double eb = DnWrap(bankWant - bank);
        if (CoAbs(bank) < 90.0) c->bankI = DnClamp(c->bankI + 0.01 * eb * dt, -0.25, 0.25);
        double uR = DnClamp(0.025 * eb - 0.005 * c->rp + c->bankI, -0.5, 0.5);
        double cb = Cos(bank * D2R);
        double uP = CoAbs(bank) > 100.0 ? 0.0                  /* upside down: roll back first, no pull at the ground */
                  : DnClamp((0.03 * (gammaWant - gamma) - 0.006 * c->rth) / (cb > 0.6 ? cb : 0.6), -0.35, 0.5);
        tR = c->sRoll * uR; tP = c->sPitch * uP;
        c->dist = rr; c->headErr = e; c->bankWant = bankWant; c->gamma = gamma;
        break;
    }
    }
    double step = (probing ? 10.0 : DN_SLEW) * dt;
    c->oR = DnSlew(c->oR, tR, step);
    c->oP = DnSlew(c->oP, tP, step);
    c->out[0] = (float)c->oP; c->out[1] = 0.0f; c->out[2] = (float)c->oR; c->out[3] = 0.0f; c->out[4] = 0.0f;
    memcpy(out, c->out, sizeof(c->out));
    return 1;
}
