// Firmware_SOLO_v2 -- MARS on ONE Teensy 4.1 = Firmware_SOLO_v1 + Bluetooth.
// The PC GUI (the MARS desktop GUI) talks to this Teensy over USB or Bluetooth, and the
// Android app (Software/MARS_App) over Bluetooth, all with the same text lines.
//
// This Teensy does everything:
//   motor        CubeMars AK10-9 V3, MIT mode, CAN1 via the MCP2551 (CTX1 pin 22, CRX1 pin 23)
//   encoders     3x AS5600, one per I2C bus (fixed address 0x36)
//                  E1 = DOF 2 shoulder : Wire2 (SCL 24, SDA 25)
//                  E2 = DOF 3 elbow    : Wire1 (SCL 16, SDA 17)
//                  E3 = DOF 4 cuff     : Wire  (SCL 19, SDA 18)
//   load cells   4 cells on one ADS1261 (SPI: CS 10, DIN 11, DOUT 12, SCLK 13, DRDY 2, RESET 3)
//   relays       brake 6, left 7, right 8, config 9, height up 0, height down 1 (active LOW)
//   bluetooth    FSC-BT986 on Serial5 (TX5 20 -> module RX, RX5 21 <- module TX), 115200,
//                transparent UART <-> BLE (service FFF0, notify FFF1, write FFF2), as DYNABO
//   control      gravity model, arm support, WINDOW mode, every safety check
//
// Loop priority: the 250 Hz motor step runs first. Everything else is short:
// one I2C transaction per pass (an encoder dropout costs well under 1 ms), the
// ADS1261 runs from its own DRDY interrupt, and telemetry is dropped rather than
// waited for when the PC is not reading USB.
//
// Frame and angles (see the MARS desktop GUI's kinematics.py):
//   z = motor shaft axis, x = pointing to the ground at the start pose.
//   theta1 (motor)  0 deg = robot plane hanging straight down, 90 deg = horizontal
//   theta2 (E1)     shoulder joint, relative to the motor link
//   theta3 (E2)     elbow joint, relative to link 1
//   theta4 (E3)     cuff joint, relative to link 2
//   All zero = every link hanging straight down (the start pose).
//
// Robot gravity torque (paper Eq. 3), fitted by the GUI calibration:
//   tau_g = g1 c1 + g2 s1 + g3 s1c2 + g4 s1c23 + g5 s1s2 + g6 s1s23
// Fallback without a fit: tau_g = a_lever * sin(theta1).
// Arm support: tau_AWS = alpha * a_arm * sin(theta1).
//
// Zero is NEVER taken at boot: HOME (= ZERO motor + EZERO encoders) is run once
// in the zero pose with the motor OFF and stored in EEPROM as offsets. The motor
// and the AS5600s are absolute, so the offsets stay valid across power cycles.
//
// WINDOW mode: the lever moves freely between win_lo and win_hi (60..120 deg).
// Inside, a weak spring (kp_center) pulls it slowly back to win_c (90 deg) on top
// of the gravity feedforward. Past a limit a stiff wall (kp_wall) pushes back, and
// win_margin past a limit is a fault (-> HOLD).
//
// Brake: solenoid powered = brake RELEASED, so with no power (or this Teensy in
// reset) the brake holds. A limit switch on the brake cuts the motor 48 V while
// the brake is applied, so the motor only has power while the brake is released.
// MANUAL for now (AUTO_BRAKE false): only BRAKE moves it. With AUTO_BRAKE true it
// follows the motor: released on EN, engaged on DIS, a fault or a lost GUI.
//
// Any fault -> HOLD at the current position. Power loss is handled by the brake.
//
// Bluetooth carries exactly the USB lines below, in both directions. Telemetry goes to
// Bluetooth only while a host is talking (any line in the last 3 s, e.g. its PING),
// at half rate (D 25 Hz, M and L 10 Hz), because a BLE link carries about 5 KB/s.
// Both links can command the robot; the 1 s heartbeat counts lines from either.
//
// Lines to the GUI (USB, 115200):
//   D,ms,mode,fault,theta,vel,tau,cur,temp,err,alpha%,alphaSet%,tff,kp,ref,cal,th2,th3,th4,enc,fb   50 Hz
//     enc: bits 0-2 encoder usable, bit 3 encoders running, bits 4-6 magnet weak/strong (warning)
//   M,ms,relayMask,seq,height,1,service,motorFb,raw1,raw2,raw3,encMask                             20 Hz
//     relayMask bit i = relay i ON (order of RLY_PIN); brake bit ON = released
//   L,ms,kg1,kg2,kg3,kg4        load cells (LC1 front-left, LC2 front-right, LC3 back-left, LC4 back-right)
//   P,key=value,...             parameters      I,text   messages      C,...   CAN frames (CANDUMP 1)
//
// Commands (one per line):
//   EN | DIS | HOLD | GO <deg> | WINDOW | ASSIST | ALPHA <0..100> | CAL LEVER | CAL ARM | UNCUFF
//   HOME | ZERO | EZERO | GSET g1..g6 | GCLR | CLEAR | SET <key> <val> | GET | CANDUMP 0|1 | PING
//   BRAKE 1|0    CFG 0|1   LEFT 0|1   RIGHT 0|1   HEIGHT UP|DOWN|STOP (repeat < 400 ms)
//   TARE         load-cell zero (motor OFF, platform unloaded)
//   SERVICE 0|1  RLY <0..5> <0|1> (SERVICE only)      v   readable encoder / load-cell print

#include <FlexCAN_T4.h>
#include <EEPROM.h>
#include <SPI.h>
#include <Wire.h>
#include <stdarg.h>

// ================================================================ configuration

// ---------------- Motor / CAN ----------------
FlexCAN_T4<CAN1, RX_SIZE_256, TX_SIZE_16> can1;   // CAN1: TX pin 22, RX pin 23
const uint8_t  MOTOR_ID = 1;        // CAN ID set in the CubeMars upper computer
const uint32_t MIT_MODE = 8;        // V3 servo firmware: MIT frame ext ID = (8 << 8) | id

// MIT packing ranges for the AK10-9 V3. Check against your manual's MIT table.
const float P_MIN = -12.56f, P_MAX = 12.56f;   // rad
const float V_MIN = -28.0f,  V_MAX = 28.0f;    // rad/s
const float T_MIN = -54.0f,  T_MAX = 54.0f;    // Nm
const float KP_MAX = 500.0f, KD_MAX = 5.0f;

// ---------------- Encoders ----------------
const uint8_t  AS5600_ADDR = 0x36;
const uint8_t  REG_STATUS  = 0x0B;   // bit5 MD magnet detected, bit4 ML weak, bit3 MH strong
const uint8_t  REG_RAW     = 0x0C;   // RAW ANGLE, 12 bit
// Bus for encoder 1, 2, 3. If the joints come out swapped, reorder these two
// arrays together (e.g. {&Wire1, &Wire, &Wire2} if enc 1 and 2 are crossed).
TwoWire* const BUS[3]      = {&Wire2, &Wire1, &Wire};
const char*    BUS_NAME[3] = {"Wire2", "Wire1", "Wire"};

// ---------------- Load cells (ADS1261, set-up from LC_Weight_COP) ----------------
const uint8_t LC_CS = 10, LC_DRDY = 2, LC_RESET = 3;
const uint8_t NUM_LC = 4;
// INPMUX codes: AIN0 = 1 ... AIN9 = 10 (0 = AINCOM). LC1..LC4 on AIN0/1, 2/3, 4/5, 6/7.
const uint8_t MUX_P[NUM_LC] = {1, 3, 5, 7};
const uint8_t MUX_N[NUM_LC] = {2, 4, 6, 8};
// counts per kg, measured at gain 32 with the internal 2.5 V reference: keep those ADC settings
const float LC_GAIN[NUM_LC] = {1.0f / 14715.83f, 1.0f / 14283.62f, 1.0f / 13688.16f, 1.0f / 14067.51f};
const uint16_t TARE_SAMPLES = 2400;

// ---------------- Relays ----------------
// Order = bit order in the M line (the GUI relies on it).
enum Rly : uint8_t { R_BRAKE, R_CFG, R_RIGHT, R_LEFT, R_HDOWN, R_HUP, N_RLY };
const uint8_t RLY_PIN[N_RLY]  = {6, 9, 8, 7, 1, 0};
const char*   RLY_NAME[N_RLY] = {"brake", "config", "right", "left", "h_down", "h_up"};
const bool    RLY_ACTIVE_LOW  = true;
const uint8_t PIN_OLD_MPWR    = 4;       // old motor power relay, now unused: kept off
const bool    AUTO_BRAKE      = false;   // true: the brake follows EN / DIS / faults (see top)

// ---------------- Bluetooth (FSC-BT986) ----------------
#define BT Serial5                       // TX5 pin 20 -> module RX, RX5 pin 21 <- module TX (3.3 V logic)
const uint32_t BT_BAUD    = 115200;      // the module's default, as on DYNABO
const uint32_t BT_IDLE_MS = 3000;        // no line from the BLE host for this long -> stop sending to it

// ---------------- Timing ----------------
const uint32_t CTRL_US         = 4000;   // 250 Hz motor control
const uint32_t ENC_STEP_US     = 3333;   // one I2C transaction per step: each encoder ~100 Hz
const uint32_t STATUS_MS       = 200;    // magnet status
const uint32_t ENC_HOLD_MS     = 60;     // a short I2C dropout keeps the last angle
const uint32_t TELEM_MS        = 20;     // 50 Hz D line
const uint32_t M_MS            = 50;     // 20 Hz M line
const uint32_t LC_MS           = 50;     // 20 Hz L line
const uint32_t GUI_TIMEOUT     = 1000;   // ms without any line (the GUI PINGs every 200 ms) -> fault
const uint32_t CAN_TIMEOUT     = 200;    // ms without motor feedback -> fault
const uint32_t CAL_MS          = 2000;   // averaging window for CAL LEVER / CAL ARM
const uint32_t BRAKE_SETTLE_MS = 300;    // solenoid travel
const uint32_t EN_FB_MS        = 5000;   // motor boot after the brake switch gives it power
const uint32_t EN_HOLD_MS      = 1000;
const uint32_t CLEAR_WAIT_MS   = 400;    // after DIS: let the expected CAN fault show up
const uint32_t HEIGHT_DEADMAN  = 400;
const uint32_t HEIGHT_DEAD_MS  = 150;    // both off before reversing

// ---------------- Tunables (SET <key> <val>) ----------------
float kpHold    = 150.0f;  // Nm/rad, HOLD / MOVE stiffness
float kdHold    = 3.0f;    // Nm*s/rad
float kpAssist  = 0.0f;    // stiffness that ASSIST ramps down to
float kdAssist  = 1.0f;    // damping during ASSIST
float kpRampS   = 5.0f;    // s to ramp kp from kpHold to kpAssist / kpCenter
float alphaRate = 10.0f;   // %/s that the actual alpha follows the set point
float moveSpeed = 15.0f;   // deg/s for GO
float tffMax    = 30.0f;   // Nm, cap on feedforward torque
float tauFault  = 40.0f;   // Nm, measured torque above this -> fault
float velFault  = 180.0f;  // deg/s, speed above this in ASSIST / WINDOW -> fault
float limLo     = -5.0f;   // deg, soft angle window for MOVE / ASSIST
float limHi     = 120.0f;
float winLo     = 60.0f;   // deg, WINDOW mode walls
float winHi     = 120.0f;
float winCenter = 90.0f;   // deg, WINDOW spring-back target
float kpCenter  = 5.0f;    // Nm/rad, WINDOW spring back to the centre (weak = slow)
float kdWin     = 1.5f;    // Nm*s/rad, WINDOW damping
float kpWall    = 300.0f;  // Nm/rad, WINDOW wall stiffness past a limit
float winMargin = 10.0f;   // deg past a wall -> fault
float tempFault = 80.0f;   // degC

// ---------------- Stored in EEPROM (same layout as Slave_02) ----------------
struct Store {
  uint32_t magic;
  float offsetRad;   // motor position (rad) in the zero pose
  float kt;          // output torque per phase amp (Nm/A), gear included
  float aLever;      // fallback robot gravity torque at 90 deg (Nm)
  int8_t dir;        // +1 / -1: motor positive = theta1 positive?
  uint8_t zeroOk, leverOk, encZeroOk;
  float eOff[3];     // encoder reading (deg) in the zero pose
  int8_t eDir[3];
  uint8_t gOk;
  float g[6];        // tau_g coefficients (Nm)
};
const uint32_t MAGIC = 0x4D415233;  // "MAR3"
Store st;

void saveStore() { EEPROM.put(0, st); }
void loadStore() {
  EEPROM.get(0, st);
  if (st.magic != MAGIC) {
    st = Store{};
    st.magic = MAGIC;
    st.kt = 1.44f;                  // 0.16 Nm/A x 9:1, placeholder
    st.dir = 1;
    for (int i = 0; i < 3; i++) st.eDir[i] = 1;
    saveStore();
  }
}

// ================================================================ state

enum Mode : uint8_t { M_OFF, M_HOLD, M_MOVE, M_ASSIST, M_WINDOW };
const char* MODE_NAME[] = {"OFF", "HOLD", "MOVE", "ASSIST", "WINDOW"};
Mode mode = M_OFF;

enum Fault : uint16_t {
  F_GUI = 1, F_CAN = 2, F_ANGLE = 4, F_TORQUE = 8,
  F_SPEED = 16, F_TEMP = 32, F_MOTOR = 64, F_PRANGE = 128, F_ENC = 256
};
uint16_t fault = 0;

// Motor feedback
float posMotor = 0;      // rad, motor frame
float curA = 0;          // phase current (A)
int8_t tempC = 0;
uint8_t motorErr = 0;
uint32_t lastFbMs = 0;
bool haveFb = false;
float bootDeg = NAN;     // first angle seen after power-up (zero sanity check)

// Derived, in the robot frame
float thDeg = 0, velDps = 0, tau = 0;
float prevThDeg = 0; uint32_t prevThUs = 0;

// Encoders
uint16_t raw[3] = {0, 0, 0};
bool readOk[3];                     // last read answered
// Magnet from the STATUS register: 0 none / never read, 1 ok, 2 weak (ML), 3 strong (MH).
// Weak / strong still give a valid angle (AGC at its limit), so they only warn.
uint8_t magnet[3] = {0, 0, 0};
uint32_t lastGoodMs[3] = {0, 0, 0};
float encRawDeg[3] = {0, 0, 0};
float th[3] = {0, 0, 0};            // theta2, theta3, theta4 (deg)
uint32_t encErrors = 0;             // I2C transactions that failed

// Command
float refDeg = 0;        // position reference
float moveTarget = 0;
float tff = 0;           // feedforward torque (robot frame)
float kpNow = 0, kdNow = 0;
float alpha = 1.0f, alphaSet = 1.0f;   // de-weighting factor, 0..1
float aArm = 0; bool armOk = false;

// CAL averaging
enum Cal : uint8_t { C_NONE, C_LEVER, C_ARM };
Cal cal = C_NONE;
uint32_t calEndMs = 0; double calTau = 0, calSin = 0; uint32_t calN = 0;

// Relays, brake sequences, height
bool rly[N_RLY];
enum Seq : uint8_t { S_IDLE, S_EN_FB, S_EN_HOLD, S_DIS_BRAKE, S_DIS_CLEAR };
Seq seq = S_IDLE;
uint32_t seqT = 0;
int8_t heightCmd = 0;        // wanted: -1 down, 0 stop, +1 up
int8_t heightOut = 0;        // what the relays do now
uint32_t heightUntil = 0, heightOffAt = 0;
bool autoClear = false;      // a plain DIS: clear the CAN fault the power cut causes
bool service = false;

// Load cells
bool lcOk = false;
float lcOff[NUM_LC] = {0, 0, 0, 0};
volatile uint8_t  lcCh = 0;
volatile int64_t  lcSum[NUM_LC];
volatile uint32_t lcN[NUM_LC];
volatile bool     tareCap = false;
volatile int64_t  tareAcc = 0;
volatile uint16_t tareGot = 0;
float lcKg[NUM_LC] = {0, 0, 0, 0};
uint32_t lcLastDataMs = 0;

uint32_t lastGuiMs = 0;
bool canDump = false;
bool verbose = false;
uint32_t usbDropped = 0;

// Bluetooth
uint8_t btTxBuf[4096], btRxBuf[1024];
uint32_t btLastRxMs = 0, btLines = 0, btDropped = 0;
bool btWasActive = false;

// ================================================================ helpers

inline float d2r(float d) { return d * 0.01745329252f; }
inline float r2d(float r) { return r * 57.2957795f; }
float clampf(float x, float lo, float hi) { return x < lo ? lo : (x > hi ? hi : x); }
float wrap180(float d) { while (d > 180) d -= 360; while (d <= -180) d += 360; return d; }

// Every line goes to USB and, while a Bluetooth host is talking, to the BT986.
// Messages and parameters always go out on USB. Telemetry (tel = true) is dropped
// when the PC is not reading, and anything that doesn't fit the Bluetooth buffer is
// dropped and counted, so neither link can stall the control loop.
enum : uint8_t { TO_USB = 1, TO_BT = 2, TO_ALL = 3 };

bool btActive() { return btLastRxMs != 0 && millis() - btLastRxMs < BT_IDLE_MS; }

void sendOut(uint8_t to, bool tel, const char* b, int n) {
  if ((to & TO_USB) && Serial) {
    if (tel && Serial.availableForWrite() < n) usbDropped++;
    else Serial.write(b, n);
  }
  if ((to & TO_BT) && btActive()) {
    if (BT.availableForWrite() < n) btDropped++;
    else BT.write(b, n);
  }
}

void sayv(uint8_t to, bool tel, const char* fmt, va_list ap) {
  char b[512];
  int n = vsnprintf(b, sizeof(b), fmt, ap);
  if (n <= 0) return;
  if (n >= (int)sizeof(b)) n = sizeof(b) - 1;
  sendOut(to, tel, b, n);
}
void say(const char* fmt, ...) { va_list ap; va_start(ap, fmt); sayv(TO_ALL, false, fmt, ap); va_end(ap); }
// Telemetry to USB only (TO_USB) or to both (TO_ALL); the caller thins the Bluetooth rate.
void tel(uint8_t to, const char* fmt, ...) { va_list ap; va_start(ap, fmt); sayv(to, true, fmt, ap); va_end(ap); }
void info(const char* s) { say("I,%s\n", s); }

bool fbFresh() { return haveFb && millis() - lastFbMs < CAN_TIMEOUT; }

void printParams();

// ================================================================ motor (CAN)

uint32_t floatToUint(float x, float lo, float hi, int bits) {
  x = clampf(x, lo, hi);
  return (uint32_t)((x - lo) * (float)((1UL << bits) - 1) / (hi - lo));
}
float uintToFloat(uint32_t x, float lo, float hi, int bits) {
  return (float)x * (hi - lo) / (float)((1UL << bits) - 1) + lo;
}

// Send one MIT command (motor frame units). V3 byte order: kp, kd, p, v, t.
void sendMit(float p, float v, float kp, float kd, float t) {
  uint32_t pi = floatToUint(p, P_MIN, P_MAX, 16);
  uint32_t vi = floatToUint(v, V_MIN, V_MAX, 12);
  uint32_t kpi = floatToUint(kp, 0, KP_MAX, 12);
  uint32_t kdi = floatToUint(kd, 0, KD_MAX, 12);
  uint32_t ti = floatToUint(t, T_MIN, T_MAX, 12);
  CAN_message_t m;
  m.id = (MIT_MODE << 8) | MOTOR_ID;
  m.flags.extended = 1;
  m.len = 8;
  m.buf[0] = kpi >> 4;
  m.buf[1] = ((kpi & 0xF) << 4) | (kdi >> 8);
  m.buf[2] = kdi & 0xFF;
  m.buf[3] = pi >> 8;
  m.buf[4] = pi & 0xFF;
  m.buf[5] = vi >> 4;
  m.buf[6] = ((vi & 0xF) << 4) | (ti >> 8);
  m.buf[7] = ti & 0xFF;
  can1.write(m);
}

// Decode feedback. Two formats are accepted:
//  - servo upload (ext ID 0x29xx): pos int16 x0.1 deg, speed, current int16 x0.01 A, temp, err
//  - classic MIT reply (std ID, buf[0] = id): p16, v12, t12, temp, err
void onCan(const CAN_message_t& m) {
  if (canDump) {
    char b[48];
    int n = snprintf(b, sizeof(b), "C,%lX,%d", (unsigned long)m.id, m.len);
    for (int i = 0; i < m.len && i < 8; i++) n += snprintf(b + n, sizeof(b) - n, ",%02X", m.buf[i]);
    tel(TO_USB, "%s\n", b);
  }
  if (m.flags.extended && (m.id >> 8) == 0x29 && (m.id & 0xFF) == MOTOR_ID && m.len >= 8) {
    int16_t p = (m.buf[0] << 8) | m.buf[1];
    int16_t c = (m.buf[4] << 8) | m.buf[5];
    posMotor = d2r(p * 0.1f);
    curA = c * 0.01f;
    tempC = (int8_t)m.buf[6];
    motorErr = m.buf[7];
  } else if (!m.flags.extended && m.len >= 6 && m.buf[0] == MOTOR_ID) {
    uint32_t p = (m.buf[1] << 8) | m.buf[2];
    uint32_t t = ((m.buf[4] & 0xF) << 8) | m.buf[5];
    posMotor = uintToFloat(p, P_MIN, P_MAX, 16);
    curA = uintToFloat(t, T_MIN, T_MAX, 12) / st.kt;   // reply carries torque
    if (m.len >= 8) { tempC = (int8_t)(m.buf[6] - 40); motorErr = m.buf[7]; }
  } else {
    return;
  }
  lastFbMs = millis();

  thDeg = st.dir * r2d(posMotor - st.offsetRad);
  tau = st.dir * curA * st.kt;
  uint32_t now = micros();
  if (haveFb) {
    float dt = (now - prevThUs) * 1e-6f;
    if (dt > 0.0005f) velDps += 0.2f * ((thDeg - prevThDeg) / dt - velDps);
  } else {
    bootDeg = thDeg;
  }
  prevThDeg = thDeg; prevThUs = now;
  haveFb = true;
}

// ================================================================ encoders

bool readReg(TwoWire* w, uint8_t reg, uint8_t n, uint8_t* out) {
  w->beginTransmission(AS5600_ADDR);
  w->write(reg);
  if (w->endTransmission(false) != 0) return false;
  if (w->requestFrom(AS5600_ADDR, n) != n) return false;
  for (uint8_t i = 0; i < n; i++) out[i] = w->read();
  return true;
}

void readAngle(int i) {
  uint8_t b[2];
  readOk[i] = readReg(BUS[i], REG_RAW, 2, b);
  if (!readOk[i]) { encErrors++; return; }
  raw[i] = ((b[0] & 0x0F) << 8) | b[1];
  lastGoodMs[i] = millis();
  encRawDeg[i] = raw[i] * (360.0f / 4096.0f);
  th[i] = wrap180(st.eDir[i] * (encRawDeg[i] - st.eOff[i]));
}

void readStatus(int i) {
  uint8_t s;
  if (!readReg(BUS[i], REG_STATUS, 1, &s)) { encErrors++; return; }   // dropout: keep the last state
  magnet[i] = !(s & 0x20) ? 0 : (s & 0x10) ? 2 : (s & 0x08) ? 3 : 1;
}

// One I2C transaction per call, so a stuck or missing encoder never holds up the motor.
void encoderStep() {
  static uint8_t k = 0;
  static int8_t statusIdx = -1;
  static uint32_t lastStatusMs = 0;
  uint32_t now = millis();
  if (statusIdx < 0 && now - lastStatusMs >= STATUS_MS) { statusIdx = 0; lastStatusMs = now; }
  if (statusIdx >= 0) {
    readStatus(statusIdx);
    if (++statusIdx >= 3) statusIdx = -1;
    return;
  }
  readAngle(k);
  k = (k + 1) % 3;
}

bool encGood(int i) { return magnet[i] != 0 && millis() - lastGoodMs[i] < ENC_HOLD_MS; }

// bits 0-2: encoder 1-3 usable; bits 3-5: its magnet is weak or strong (warning only)
uint8_t encMask() {
  uint8_t m = 0;
  for (int i = 0; i < 3; i++) {
    if (encGood(i)) m |= 1 << i;
    if (magnet[i] >= 2) m |= 8 << i;
  }
  return m;
}

// tau_g needs theta2 and theta3 (encoders 1 and 2)
bool encUsable() { return (encMask() & 3) == 3 && st.encZeroOk; }

// ================================================================ load cells

SPISettings lcSpi(5000000, MSBFIRST, SPI_MODE1);

static inline void lcSelect()   { digitalWriteFast(LC_CS, LOW); }
static inline void lcDeselect() { digitalWriteFast(LC_CS, HIGH); }
static inline uint8_t muxCode(uint8_t ch) { return (uint8_t)(((MUX_P[ch] & 0x0F) << 4) | (MUX_N[ch] & 0x0F)); }

void lcWrite(uint8_t reg, uint8_t val) {
  lcSelect(); SPI.transfer((uint8_t)(0x40 | reg)); SPI.transfer(val); lcDeselect();
}
uint8_t lcRead(uint8_t reg) {
  lcSelect(); SPI.transfer((uint8_t)(0x20 | reg)); SPI.transfer(0x00);
  uint8_t v = SPI.transfer(0x00); lcDeselect();
  return v;
}
void lcStartConv() { lcSelect(); SPI.transfer((uint8_t)0x08); lcDeselect(); }
void lcStopConv()  { lcSelect(); SPI.transfer((uint8_t)0x0A); lcDeselect(); }

int32_t lcReadConv() {
  lcSelect();
  SPI.transfer((uint8_t)0x12);   // RDATA
  (void)SPI.transfer((uint8_t)0x00);
  uint8_t b2 = SPI.transfer((uint8_t)0x00);
  uint8_t b1 = SPI.transfer((uint8_t)0x00);
  uint8_t b0 = SPI.transfer((uint8_t)0x00);
  lcDeselect();
  int32_t v = ((int32_t)b2 << 16) | ((int32_t)b1 << 8) | (int32_t)b0;
  if (v & 0x800000) v |= 0xFF000000;
  return v;
}

// DRDY: read the conversion, then switch the input to the next cell (writing
// INPMUX restarts the conversion). During a tare the input stays on one cell.
void lcIsr() {
  if (digitalReadFast(LC_DRDY) != LOW) return;
  int32_t v = lcReadConv();
  if (tareCap) {
    if (tareGot < TARE_SAMPLES) { tareAcc += v; tareGot++; }
    return;
  }
  lcSum[lcCh] += v;
  lcN[lcCh]++;
  lcCh = (uint8_t)((lcCh + 1) % NUM_LC);
  lcSelect(); SPI.transfer((uint8_t)(0x40 | 0x11)); SPI.transfer(muxCode(lcCh)); lcDeselect();
}

// The SPI transaction stays open while acquiring (only the ADS1261 is on SPI).
void lcStopAcq() {
  detachInterrupt(digitalPinToInterrupt(LC_DRDY));
  lcStopConv();
  SPI.endTransaction();
}

void lcStartAcq() {
  SPI.beginTransaction(lcSpi);
  noInterrupts();
  lcCh = 0;
  for (uint8_t i = 0; i < NUM_LC; i++) { lcSum[i] = 0; lcN[i] = 0; }
  interrupts();
  lcWrite(0x11, muxCode(0));
  attachInterrupt(digitalPinToInterrupt(LC_DRDY), lcIsr, FALLING);
  lcStartConv();
}

// Mean raw counts of one cell, input held on it (~60 ms).
float lcCaptureOffset(uint8_t ch) {
  SPI.beginTransaction(lcSpi);
  lcWrite(0x11, muxCode(ch));
  noInterrupts();
  tareAcc = 0; tareGot = 0; tareCap = true;
  interrupts();
  attachInterrupt(digitalPinToInterrupt(LC_DRDY), lcIsr, FALLING);
  lcStartConv();
  uint32_t t0 = millis();
  while (tareGot < TARE_SAMPLES && millis() - t0 < 500) {}
  lcStopConv();
  detachInterrupt(digitalPinToInterrupt(LC_DRDY));
  noInterrupts();
  int64_t acc = tareAcc; uint16_t got = tareGot; tareCap = false;
  interrupts();
  SPI.endTransaction();
  if (got == 0) { say("I,LC%u: no data during tare (DRDY?)\n", ch + 1); return lcOff[ch]; }
  return (float)((double)acc / got);
}

// Blocks ~0.3 s: only while the motor is OFF (and at boot).
void lcTare() {
  lcStopAcq();
  for (uint8_t i = 0; i < NUM_LC; i++) lcOff[i] = lcCaptureOffset(i);
  say("I,load cells tared (raw %.0f %.0f %.0f %.0f)\n", lcOff[0], lcOff[1], lcOff[2], lcOff[3]);
  lcStartAcq();
}

void lcBegin() {
  pinMode(LC_CS, OUTPUT);
  pinMode(LC_DRDY, INPUT);
  pinMode(LC_RESET, OUTPUT);
  digitalWriteFast(LC_CS, HIGH);
  digitalWriteFast(LC_RESET, LOW); delayMicroseconds(10); digitalWriteFast(LC_RESET, HIGH);
  delay(5);
  SPI.begin();
  SPI.beginTransaction(lcSpi);
  lcWrite(0x02, 0x83);  // MODE0: 40 kSPS, sinc4
  lcWrite(0x03, 0x01);  // MODE1: continuous, 50 us start delay
  lcWrite(0x05, 0x00);  // MODE3: no status byte, no CRC
  lcWrite(0x06, 0x10);  // REF:   internal 2.5 V reference
  lcWrite(0x10, 0x05);  // PGA:   gain 32
  uint8_t ref = lcRead(0x06), pga = lcRead(0x10);
  SPI.endTransaction();
  lcOk = (pga == 0x05 && ref == 0x10);
  if (!lcOk) { say("I,ADS1261 not found (REF 0x%02X PGA 0x%02X): load cells off\n", ref, pga); return; }
  lcTare();   // at boot the platform should be unloaded
}

// 20 Hz: average of the conversions since the last call, as kg.
void lcOutput() {
  if (!lcOk) return;
  int64_t sum[NUM_LC]; uint32_t n[NUM_LC];
  noInterrupts();
  for (uint8_t i = 0; i < NUM_LC; i++) { sum[i] = lcSum[i]; n[i] = lcN[i]; lcSum[i] = 0; lcN[i] = 0; }
  interrupts();
  uint32_t now = millis();
  for (uint8_t i = 0; i < NUM_LC; i++) {
    if (n[i] == 0) {
      if (now - lcLastDataMs > 2000) { info("load cells: no conversions (DRDY wire / ADC power?)"); lcLastDataMs = now; }
      return;
    }
  }
  lcLastDataMs = now;
  for (uint8_t i = 0; i < NUM_LC; i++) lcKg[i] = ((float)((double)sum[i] / n[i]) - lcOff[i]) * LC_GAIN[i];
  static uint8_t k = 0;
  tel((++k & 1) ? TO_ALL : TO_USB, "L,%lu,%.3f,%.3f,%.3f,%.3f\n", now, lcKg[0], lcKg[1], lcKg[2], lcKg[3]);
}

// ================================================================ relays, brake, height

void setRly(uint8_t i, bool on) {
  rly[i] = on;
  digitalWrite(RLY_PIN[i], (on != RLY_ACTIVE_LOW) ? HIGH : LOW);
}

bool brakeEngaged() { return !rly[R_BRAKE]; }
bool holding() { return mode != M_OFF; }

uint8_t relayMask() {
  uint8_t m = 0;
  for (int i = 0; i < N_RLY; i++) if (rly[i]) m |= 1 << i;
  return m;
}

void engageBrake(const char* why) {
  if (!brakeEngaged()) {
    setRly(R_BRAKE, false);
    say("I,brake ENGAGED (%s)\n", why);
  }
}

void setHeight(int8_t dir) {
  setRly(R_HUP, dir > 0);
  setRly(R_HDOWN, dir < 0);
  heightOut = dir;
}

void runHeight() {
  uint32_t now = millis();
  int8_t want = heightCmd;
  if (want && now > heightUntil) want = heightCmd = 0;               // button released
  if (want == heightOut) return;
  if (heightOut != 0) { setHeight(0); heightOffAt = now; return; }   // stop first
  if (now - heightOffAt < HEIGHT_DEAD_MS) return;                     // relay dead time
  setHeight(want);
}

// ================================================================ control

float robotModel(float deg) {
  float s1 = sinf(d2r(deg));
  if (st.gOk) {
    if (!encUsable()) return st.leverOk ? st.aLever * s1 : 0.0f;   // fault is raised separately
    float c1 = cosf(d2r(deg));
    float t2 = d2r(th[0]), t23 = d2r(th[0] + th[1]);
    return st.g[0] * c1 + st.g[1] * s1 + st.g[2] * s1 * cosf(t2) + st.g[3] * s1 * cosf(t23)
         + st.g[4] * s1 * sinf(t2) + st.g[5] * s1 * sinf(t23);
  }
  return st.leverOk ? st.aLever * s1 : 0.0f;
}
bool robotModelOk() { return st.gOk || st.leverOk; }

void enterHold(float deg, float ff) {
  mode = M_HOLD;
  refDeg = deg; tff = ff;
  kpNow = kpHold; kdNow = kdHold;
  cal = C_NONE;
}

void raiseFault(uint16_t f, const char* why) {
  if (fault & f) return;
  fault |= f;
  say("I,FAULT %s\n", why);
  // Already holding: keep the reference, or every fault re-centres on the sagged
  // angle and the lever creeps down. MOVE / ASSIST / WINDOW hold where the lever is now.
  if (mode == M_HOLD) enterHold(refDeg, tff);
  else if (mode != M_OFF) enterHold(thDeg, tff);
}

void checkFaults(uint32_t nowMs) {
  if (mode == M_OFF) return;
  if (nowMs - lastGuiMs > GUI_TIMEOUT) raiseFault(F_GUI, "gui link lost");
  if (nowMs - lastFbMs > CAN_TIMEOUT)  raiseFault(F_CAN, "no motor feedback (brake must take over)");
  if (fabsf(tau) > tauFault)           raiseFault(F_TORQUE, "over torque");
  if (tempC > tempFault)               raiseFault(F_TEMP, "over temperature");
  if (motorErr != 0)                   raiseFault(F_MOTOR, "motor error code");
  if ((mode == M_MOVE || mode == M_ASSIST) && (thDeg < limLo || thDeg > limHi))
    raiseFault(F_ANGLE, "angle outside window");
  if (mode == M_WINDOW && (thDeg < winLo - winMargin || thDeg > winHi + winMargin))
    raiseFault(F_ANGLE, "angle past a WINDOW wall");
  if ((mode == M_ASSIST || mode == M_WINDOW) && fabsf(velDps) > velFault) raiseFault(F_SPEED, "over speed");
  if (st.gOk && !encUsable() && (mode == M_MOVE || mode == M_ASSIST || mode == M_WINDOW))
    raiseFault(F_ENC, "encoders lost while the tau_g model is in use");
}

// The arm's share of the feedforward, alpha following alphaSet at alphaRate.
float armFf(float dt) {
  float da = alphaRate * 0.01f * dt;
  alpha += clampf(alphaSet - alpha, -da, da);
  return armOk ? alpha * aArm * sinf(d2r(thDeg)) : 0.0f;
}

void control(float dt) {
  float wallDeg = NAN;     // WINDOW: the limit the lever is past, if any
  switch (mode) {
    case M_OFF:
      // Zero gains: the motor is free but keeps sending feedback.
      sendMit(0, 0, 0, 0, 0);
      return;

    case M_HOLD:
      break;

    case M_MOVE: {
      float step = moveSpeed * dt;
      float e = moveTarget - refDeg;
      refDeg += clampf(e, -step, step);
      tff = robotModel(refDeg);
      if (fabsf(moveTarget - refDeg) < 1e-3f) { enterHold(moveTarget, tff); info("reached target, HOLD"); }
      break;
    }

    case M_ASSIST: {
      float dk = (kpHold - kpAssist) / max(kpRampS, 0.1f) * dt;
      kpNow += clampf(kpAssist - kpNow, -dk, dk);
      kdNow = kdAssist;
      tff = robotModel(thDeg) + armFf(dt);
      break;
    }

    case M_WINDOW: {
      // kp ramps down to the centre spring while the reference walks to the
      // centre, so entering from HOLD never jerks.
      float dk = (kpHold - kpCenter) / max(kpRampS, 0.1f) * dt;
      kpNow += clampf(kpCenter - kpNow, -dk, dk);
      kdNow = kdWin;
      float step = moveSpeed * dt;
      refDeg += clampf(winCenter - refDeg, -step, step);
      tff = robotModel(thDeg) + armFf(dt);
      if (thDeg > winHi) wallDeg = winHi;
      else if (thDeg < winLo) wallDeg = winLo;
      break;
    }
  }

  // One MIT spring = centre spring + wall spring (same torque at every angle).
  float kpCmd = kpNow, pDeg = refDeg;
  if (!isnan(wallDeg)) {
    kpCmd = clampf(kpNow + kpWall, 0, KP_MAX);
    pDeg = (kpNow * refDeg + (kpCmd - kpNow) * wallDeg) / kpCmd;
  }

  tff = clampf(tff, -tffMax, tffMax);
  float pMotor = st.offsetRad + st.dir * d2r(pDeg);
  if (pMotor < P_MIN || pMotor > P_MAX) {
    raiseFault(F_PRANGE, "target outside motor MIT range (re-ZERO?)");
    pMotor = clampf(pMotor, P_MIN, P_MAX);
  }
  sendMit(pMotor, 0, kpCmd, kdNow, st.dir * tff);

  // CAL averaging (only while holding still)
  if (cal != C_NONE) {
    calTau += (cal == C_ARM) ? tau - robotModel(thDeg) : tau;
    calSin += sinf(d2r(thDeg)); calN++;
    if (millis() >= calEndMs) {
      float a = (float)(calTau / calSin);
      if (cal == C_LEVER) {
        st.aLever = a; st.leverOk = 1; saveStore();
        say("I,lever torque at 90 deg = %.3f Nm (saved)\n", a);
      } else {
        aArm = a; armOk = true;
        say("I,arm torque at 90 deg = %.3f Nm\n", aArm);
      }
      cal = C_NONE;
      printParams();
    }
  }
}

// ================================================================ brake sequences (AUTO_BRAKE)

void motorCommand(char* line);

void motorCmd(const char* s) {
  char b[32];
  strlcpy(b, s, sizeof(b));
  motorCommand(b);
}

// Brake on, then (after the solenoid has moved) motor off. Applying the brake
// cuts the motor power through the limit switch, so the motor holds until then.
// trip = a safety stop: the fault stays latched for the user to read.
void startDisable(const char* why, bool trip) {
  engageBrake(why);
  autoClear = !trip && fault == 0;
  seq = S_DIS_BRAKE; seqT = millis();
}

void setBrake(bool engage) {
  if (seq != S_IDLE) { info("BRAKE ignored: sequence running"); return; }
  if (engage) {
    if (holding()) info("brake ENGAGED: motor power cut while the motor was enabled");
    else info(brakeEngaged() ? "brake already engaged" : "brake ENGAGED (motor power cut)");
    setRly(R_BRAKE, false);
  } else {
    setRly(R_BRAKE, true);
    info("brake RELEASED: motor powered, lever held by the motor only once it is enabled");
  }
}

void startEnable() {
  if (!AUTO_BRAKE) {
    if (brakeEngaged()) { info("EN refused: brake is on (no motor power). Release the brake first"); return; }
    motorCmd("EN");
    return;
  }
  if (seq != S_IDLE) { info("EN ignored: busy"); return; }
  if (fault)         { info("EN refused: clear the fault first"); return; }
  if (holding() && !brakeEngaged()) { info("already enabled"); return; }
  setRly(R_BRAKE, true);
  info("brake RELEASED, waiting for motor power and feedback...");
  seq = S_EN_FB; seqT = millis();
}

void runSeq() {
  uint32_t dt = millis() - seqT;
  switch (seq) {
    case S_IDLE: return;
    case S_EN_FB:
      if (fbFresh()) { motorCmd("EN"); seq = S_EN_HOLD; seqT = millis(); }
      else if (dt >= EN_FB_MS) startDisable("EN failed: no motor feedback after brake release", true);
      return;
    case S_EN_HOLD:
      if (holding() && !fault) { seq = S_IDLE; info("ENABLED: motor holding, brake released"); }
      else if (dt >= EN_HOLD_MS) startDisable("EN failed: motor did not enter HOLD", true);
      return;
    case S_DIS_BRAKE:
      if (dt >= BRAKE_SETTLE_MS) { motorCmd("DIS"); seq = S_DIS_CLEAR; seqT = millis(); }
      return;
    case S_DIS_CLEAR:
      if (dt >= CLEAR_WAIT_MS) {
        seq = S_IDLE;
        if (autoClear && fault == F_CAN) motorCmd("CLEAR");   // only the expected power cut
        info("DISABLED: brake on, motor power cut by the brake switch");
      }
      return;
  }
}

void safety() {
  uint32_t now = millis();
  bool guiLost = now - lastGuiMs > GUI_TIMEOUT;
  if (guiLost) {
    heightCmd = 0;
    if (service) { service = false; info("SERVICE off (gui link lost)"); }
  }
  if (!AUTO_BRAKE || service || brakeEngaged()) return;
  const char* why = nullptr;
  if (guiLost)        why = "gui link lost";
  else if (fault)     why = "fault";
  else if (seq == S_IDLE) {                      // the EN sequence has its own timeouts
    if (!fbFresh())   why = "no motor feedback (CAN)";
    else if (!holding()) why = "motor not holding";
  }
  if (why) startDisable(why, true);
}

// ================================================================ commands

void printParams() {
  say("P,offset=%.5f,dir=%d,kt=%.4f,zero_ok=%d,a_lever=%.3f,lever_ok=%d,a_arm=%.3f,arm_ok=%d,"
      "kp_hold=%.1f,kd_hold=%.2f,kp_assist=%.1f,kd_assist=%.2f,kp_ramp=%.1f,a_rate=%.1f,"
      "mv_speed=%.1f,tff_max=%.1f,tau_fault=%.1f,vel_fault=%.0f,lim_lo=%.1f,lim_hi=%.1f,boot=%.1f,",
      st.offsetRad, st.dir, st.kt, st.zeroOk, st.aLever, st.leverOk, aArm, armOk,
      kpHold, kdHold, kpAssist, kdAssist, kpRampS, alphaRate,
      moveSpeed, tffMax, tauFault, velFault, limLo, limHi, bootDeg);
  say("enc_zero_ok=%d,e1_off=%.2f,e2_off=%.2f,e3_off=%.2f,e1_dir=%d,e2_dir=%d,e3_dir=%d,enc_bad=%lu,"
      "usb_drop=%lu,bt=%d,bt_drop=%lu,lc_ok=%d,g_ok=%d,g1=%.4f,g2=%.4f,g3=%.4f,g4=%.4f,g5=%.4f,g6=%.4f,",
      st.encZeroOk, st.eOff[0], st.eOff[1], st.eOff[2], st.eDir[0], st.eDir[1], st.eDir[2],
      encErrors, usbDropped, btActive() ? 1 : 0, btDropped, lcOk, st.gOk,
      st.g[0], st.g[1], st.g[2], st.g[3], st.g[4], st.g[5]);
  say("win_lo=%.1f,win_hi=%.1f,win_c=%.1f,kp_center=%.1f,kd_win=%.2f,kp_wall=%.1f,win_margin=%.1f\n",
      winLo, winHi, winCenter, kpCenter, kdWin, kpWall, winMargin);
}

bool setParam(const char* k, float v) {
  if (!strcmp(k, "kp_hold"))   { kpHold = clampf(v, 0, KP_MAX); return true; }
  if (!strcmp(k, "kd_hold"))   { kdHold = clampf(v, 0, KD_MAX); return true; }
  if (!strcmp(k, "kp_assist")) { kpAssist = clampf(v, 0, KP_MAX); return true; }
  if (!strcmp(k, "kd_assist")) { kdAssist = clampf(v, 0, KD_MAX); return true; }
  if (!strcmp(k, "kp_ramp"))   { kpRampS = max(v, 0.1f); return true; }
  if (!strcmp(k, "a_rate"))    { alphaRate = clampf(v, 0.1f, 100); return true; }
  if (!strcmp(k, "mv_speed"))  { moveSpeed = clampf(v, 1, 60); return true; }
  if (!strcmp(k, "tff_max"))   { tffMax = clampf(v, 0, T_MAX); return true; }
  if (!strcmp(k, "tau_fault")) { tauFault = clampf(v, 1, T_MAX); return true; }
  if (!strcmp(k, "vel_fault")) { velFault = clampf(v, 10, 720); return true; }
  if (!strcmp(k, "lim_lo"))    { limLo = v; return true; }
  if (!strcmp(k, "lim_hi"))    { limHi = v; return true; }
  if (!strcmp(k, "kp_center")) { kpCenter = clampf(v, 0, 50); return true; }
  if (!strcmp(k, "kd_win"))    { kdWin = clampf(v, 0, KD_MAX); return true; }
  if (!strcmp(k, "kp_wall"))   { kpWall = clampf(v, 0, KP_MAX); return true; }
  if (!strcmp(k, "win_margin")) { winMargin = clampf(v, 2, 30); return true; }
  // The window changes only outside WINDOW mode and must keep lo < c < hi.
  if (!strcmp(k, "win_lo") || !strcmp(k, "win_hi") || !strcmp(k, "win_c")) {
    if (mode == M_WINDOW) { info("window limits not during WINDOW (HOLD first)"); return true; }
    float lo = winLo, hi = winHi, c = winCenter;
    if (!strcmp(k, "win_lo")) lo = v; else if (!strcmp(k, "win_hi")) hi = v; else c = v;
    if (!(lo < c && c < hi)) { info("window needs win_lo < win_c < win_hi"); return true; }
    winLo = lo; winHi = hi; winCenter = c; return true;
  }
  if (!strcmp(k, "kt"))        { st.kt = max(v, 0.01f); saveStore(); return true; }
  if (!strcmp(k, "a_lever"))   { st.aLever = v; st.leverOk = 1; saveStore(); return true; }
  if (!strcmp(k, "a_arm"))     { aArm = v; armOk = true; return true; }
  if (!strcmp(k, "dir")) {
    if (mode != M_OFF) { info("DIR only when OFF"); return true; }
    st.dir = v < 0 ? -1 : 1; st.zeroOk = 0; saveStore();
    info("DIR changed: re-ZERO needed"); return true;
  }
  // e1_dir..e3_dir: flip an encoder; its zero stays valid (offset is in raw degrees)
  if (k[0] == 'e' && k[1] >= '1' && k[1] <= '3' && !strcmp(k + 2, "_dir")) {
    if (mode == M_ASSIST || mode == M_WINDOW) { info("encoder DIR not during ASSIST / WINDOW"); return true; }
    st.eDir[k[1] - '1'] = v < 0 ? -1 : 1; saveStore(); return true;
  }
  return false;
}

// Motor and model commands (what Slave_02 used to handle).
void motorCommand(char* line) {
  char* cmd = strtok(line, " ");
  if (!cmd) return;
  char* a[6];
  for (int i = 0; i < 6; i++) a[i] = strtok(nullptr, " ");
  char* a1 = a[0];
  char* a2 = a[1];

  if (!strcmp(cmd, "PING")) return;

  if (!strcmp(cmd, "EN")) {
    if (mode != M_OFF) return;
    if (!fbFresh()) { info("no motor feedback, cannot enable (motor power on?)"); return; }
    if (!st.zeroOk) info("WARNING: zero not set");
    enterHold(thDeg, robotModel(thDeg));
    info("enabled, HOLD at current position");
  } else if (!strcmp(cmd, "DIS")) {
    mode = M_OFF; cal = C_NONE; info("disabled (motor free)");
  } else if (!strcmp(cmd, "ZERO")) {
    if (mode != M_OFF) { info("ZERO only when OFF, in the zero pose"); return; }
    if (!haveFb) { info("no motor feedback"); return; }
    st.offsetRad = posMotor; st.zeroOk = 1; saveStore();
    info("motor zero set and saved"); printParams();
  } else if (!strcmp(cmd, "EZERO")) {
    if (mode != M_OFF) { info("EZERO only when OFF, in the zero pose"); return; }
    if ((encMask() & 7) != 7) { info("EZERO refused: an encoder is not answering"); return; }
    for (int i = 0; i < 3; i++) st.eOff[i] = encRawDeg[i];
    st.encZeroOk = 1; saveStore();
    info("encoder zero set and saved"); printParams();
  } else if (!strcmp(cmd, "HOME")) {
    // ZERO + EZERO in one step: every link hanging straight down, motor OFF.
    if (mode != M_OFF) { info("HOME only when OFF, in the zero pose"); return; }
    if (!haveFb) { info("HOME refused: no motor feedback"); return; }
    if ((encMask() & 7) != 7) { info("HOME refused: an encoder is not answering"); return; }
    st.offsetRad = posMotor; st.zeroOk = 1;
    for (int i = 0; i < 3; i++) st.eOff[i] = encRawDeg[i];
    st.encZeroOk = 1; saveStore();
    info("HOME set and saved: motor + 3 encoders = 0"); printParams();
  } else if (!strcmp(cmd, "WINDOW")) {
    if (mode != M_HOLD || fault) { info("WINDOW needs HOLD and no fault"); return; }
    if (!st.zeroOk) { info("WINDOW refused: zero not set (HOME)"); return; }
    if (thDeg < winLo || thDeg > winHi) { info("WINDOW refused: lever outside the window (GO 90 first)"); return; }
    if (st.gOk && !encUsable()) { info("WINDOW refused: tau_g model needs the encoders"); return; }
    mode = M_WINDOW; refDeg = thDeg; kpNow = kpHold; cal = C_NONE;
    say("I,WINDOW %.0f..%.0f deg, springs back to %.0f\n", winLo, winHi, winCenter);
  } else if (!strcmp(cmd, "GO")) {
    float d = a1 ? atof(a1) : 90.0f;
    if (mode == M_OFF || fault) { info("GO needs EN and no fault"); return; }
    if (!st.zeroOk) { info("GO refused: zero not set"); return; }
    if (d < limLo || d > limHi) { info("GO refused: outside angle window"); return; }
    if (st.gOk && !encUsable()) { info("GO refused: tau_g model needs the encoders"); return; }
    moveTarget = d;
    if (mode != M_MOVE) { refDeg = thDeg; kpNow = kpHold; kdNow = kdHold; }
    mode = M_MOVE; cal = C_NONE;
    say("I,moving to %.1f deg\n", d);
  } else if (!strcmp(cmd, "HOLD")) {
    if (mode == M_OFF) return;
    enterHold(thDeg, tff); info("HOLD at current position");
  } else if (!strcmp(cmd, "CAL")) {
    if (mode != M_HOLD || fault) { info("CAL needs HOLD and no fault"); return; }
    if (thDeg < 30) { info("CAL needs the motor above 30 deg (use GO 90)"); return; }
    bool lever = a1 && !strcmp(a1, "LEVER");
    if (!lever && !robotModelOk()) { info("CAL ARM needs a robot model (calibration or CAL LEVER)"); return; }
    cal = lever ? C_LEVER : C_ARM;
    calTau = calSin = 0; calN = 0; calEndMs = millis() + CAL_MS;
    info(lever ? "measuring lever..." : "measuring arm...");
  } else if (!strcmp(cmd, "ASSIST")) {
    if (mode != M_HOLD || fault) { info("ASSIST needs HOLD and no fault"); return; }
    if (!robotModelOk() || !armOk) { info("ASSIST needs a robot model and CAL ARM"); return; }
    // Re-centre on the current (sagged) angle: the feedforward now carries the
    // load, so the spring must start unloaded or the lever jerks up.
    mode = M_ASSIST; alpha = 1.0f; kpNow = kpHold; refDeg = thDeg;
    info("ASSIST: handing over the arm load");
  } else if (!strcmp(cmd, "UNCUFF")) {
    if (mode == M_ASSIST || mode == M_WINDOW) { info("UNCUFF not during ASSIST / WINDOW (HOLD first)"); return; }
    armOk = false; aArm = 0; info("arm removed"); printParams();
  } else if (!strcmp(cmd, "ALPHA")) {
    if (a1) alphaSet = clampf(atof(a1), 0, 100) * 0.01f;
  } else if (!strcmp(cmd, "GSET")) {
    if (mode == M_ASSIST || mode == M_WINDOW) { info("GSET not during ASSIST / WINDOW"); return; }
    for (int i = 0; i < 6; i++) if (!a[i]) { info("GSET needs 6 values"); return; }
    for (int i = 0; i < 6; i++) st.g[i] = atof(a[i]);
    st.gOk = 1; saveStore();
    info("tau_g model set and saved"); printParams();
  } else if (!strcmp(cmd, "GCLR")) {
    if (mode == M_ASSIST || mode == M_WINDOW) { info("GCLR not during ASSIST / WINDOW"); return; }
    st.gOk = 0; saveStore(); info("tau_g model cleared"); printParams();
  } else if (!strcmp(cmd, "CLEAR")) {
    fault = 0; info("faults cleared");
  } else if (!strcmp(cmd, "SET")) {
    if (a1 && a2 && setParam(a1, atof(a2))) printParams();
    else info("unknown SET key");
  } else if (!strcmp(cmd, "GET")) {
    printParams();
  } else if (!strcmp(cmd, "CANDUMP")) {
    canDump = a1 && atoi(a1);
  } else {
    info("unknown command");
  }
}

// Every line from the GUI: brake / relay / load-cell commands here, the rest to motorCommand.
void handle(char* line) {
  lastGuiMs = millis();
  char cmd[24] = "", a1[16] = "", a2[16] = "";
  sscanf(line, "%23s %15s %15s", cmd, a1, a2);
  if (!cmd[0]) return;

  if (!strcmp(cmd, "v")) { verbose = !verbose; return; }

  if (!strcmp(cmd, "EN")) {
    startEnable();
  } else if (!strcmp(cmd, "DIS")) {
    if (AUTO_BRAKE && !brakeEngaged()) startDisable("disable", false);
    else if (seq == S_IDLE) motorCmd("DIS");
  } else if (!strcmp(cmd, "BRAKE")) {
    if (!a1[0]) { info("BRAKE 1 (engage) | BRAKE 0 (release)"); return; }
    setBrake(atoi(a1) != 0);
  } else if (!strcmp(cmd, "CFG") || !strcmp(cmd, "LEFT") || !strcmp(cmd, "RIGHT") ||
             !strcmp(cmd, "LIMMAX") || !strcmp(cmd, "LIMMIN")) {
    uint8_t r = !strcmp(cmd, "CFG") ? R_CFG
              : (!strcmp(cmd, "LEFT") || !strcmp(cmd, "LIMMAX")) ? R_LEFT : R_RIGHT;
    setRly(r, atoi(a1) != 0);
    say("I,%s solenoid %s\n", RLY_NAME[r], rly[r] ? "ON" : "off");
  } else if (!strcmp(cmd, "HEIGHT")) {
    if (!strcmp(a1, "UP") || !strcmp(a1, "DOWN")) {
      heightCmd = !strcmp(a1, "UP") ? 1 : -1;
      heightUntil = millis() + HEIGHT_DEADMAN;
    } else heightCmd = 0;
  } else if (!strcmp(cmd, "TARE")) {
    if (!lcOk) { info("TARE: load cells not found"); return; }
    if (mode != M_OFF) { info("TARE only with the motor OFF (it pauses the loop ~0.3 s)"); return; }
    heightCmd = 0; setHeight(0);
    lcTare();
  } else if (!strcmp(cmd, "SERVICE")) {
    service = atoi(a1) != 0;
    info(service ? "SERVICE ON: raw relays allowed, auto-brake off" : "SERVICE off");
  } else if (!strcmp(cmd, "RLY")) {
    int i = atoi(a1);
    if (!service) { info("RLY needs SERVICE 1"); return; }
    if (i < 0 || i >= N_RLY || !a2[0]) { say("I,RLY <0..%d> <0|1>\n", N_RLY - 1); return; }
    if ((i == R_HUP || i == R_HDOWN) && atoi(a2)) { info("use HEIGHT for the actuator"); return; }
    setRly(i, atoi(a2) != 0);
    say("I,relay %d (%s) %s\n", i, RLY_NAME[i], rly[i] ? "ON" : "off");
  } else if (!service && brakeEngaged() &&
             (!strcmp(cmd, "GO") || !strcmp(cmd, "ASSIST") || !strcmp(cmd, "WINDOW") || !strcmp(cmd, "CAL"))) {
    say("I,%s refused: brake is on (EN first)\n", cmd);
  } else {
    motorCommand(line);
  }
}

void readGui() {
  static char buf[176]; static uint8_t n = 0;
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\n' || c == '\r') {
      if (n) { buf[n] = 0; handle(buf); n = 0; }
    } else if (n < sizeof(buf) - 1) buf[n++] = c;
  }
}

// Lines from the Bluetooth host: the same commands as USB. The module's own status
// lines (AT replies such as "OK" or "+...") go to USB only and are otherwise ignored.
void readBt() {
  static char buf[176]; static uint8_t n = 0;
  while (BT.available()) {
    char c = BT.read();
    if (c == '\n' || c == '\r') {
      if (!n) continue;
      buf[n] = 0; n = 0;
      if (buf[0] == '+' || !strcmp(buf, "OK") || !strncmp(buf, "AT", 2)) {
        if (Serial) Serial.printf("I,bt module: %s\n", buf);
        continue;
      }
      btLastRxMs = millis();
      btLines++;
      handle(buf);
    } else if (n < sizeof(buf) - 1) buf[n++] = c;
  }
  bool act = btActive();
  if (act != btWasActive) {
    btWasActive = act;
    info(act ? "bluetooth host connected" : "bluetooth host silent (no line for 3 s)");
    if (act) printParams();
  }
}

// ================================================================ telemetry

void sendD() {
  uint8_t m = encMask();
  uint8_t enc = (m & 7) | 8 | ((m >> 3) << 4);
  static uint8_t k = 0;
  tel((++k & 1) ? TO_ALL : TO_USB,
      "D,%lu,%s,%u,%.2f,%.1f,%.3f,%.2f,%d,%u,%.1f,%.1f,%.3f,%.1f,%.2f,%u,%.2f,%.2f,%.2f,%u,%d\n",
      millis(), MODE_NAME[mode], fault, thDeg, velDps, tau, curA, tempC, motorErr,
      alpha * 100, alphaSet * 100, tff, kpNow, refDeg, cal, th[0], th[1], th[2], enc, fbFresh() ? 1 : 0);
}

void sendM() {
  static uint8_t k = 0;
  tel((++k & 1) ? TO_ALL : TO_USB, "M,%lu,%u,%u,%d,1,%d,%d,%u,%u,%u,%u\n", millis(), relayMask(), seq, heightOut,
      service ? 1 : 0, fbFresh() ? 1 : 0, raw[0], raw[1], raw[2], encMask());
}

void printVerbose() {
  static const char* MAG[] = {"NO MAG", "ok", "WEAK", "STRONG"};
  for (int i = 0; i < 3; i++)
    Serial.printf("E%d[%s] %4u %7.2f deg %-6s  ", i + 1, BUS_NAME[i], raw[i], raw[i] * 360.0f / 4096.0f,
                  !readOk[i] ? "NO I2C" : MAG[magnet[i]]);
  if (lcOk) Serial.printf("| kg %.2f %.2f %.2f %.2f", lcKg[0], lcKg[1], lcKg[2], lcKg[3]);
  Serial.printf("  | i2c err %lu  | bt %s, %lu lines, %lu dropped\n", encErrors,
                btActive() ? "host" : "idle", btLines, btDropped);
}

// ================================================================ Arduino

void setup() {
  // Relays off before the pins become outputs: brake engaged, height stopped, no glitch.
  for (int i = 0; i < N_RLY; i++) {
    digitalWrite(RLY_PIN[i], RLY_ACTIVE_LOW ? HIGH : LOW);
    pinMode(RLY_PIN[i], OUTPUT);
    rly[i] = false;
  }
  digitalWrite(PIN_OLD_MPWR, RLY_ACTIVE_LOW ? HIGH : LOW);
  pinMode(PIN_OLD_MPWR, OUTPUT);

  Serial.begin(115200);
  BT.begin(BT_BAUD);
  BT.addMemoryForWrite(btTxBuf, sizeof(btTxBuf));
  BT.addMemoryForRead(btRxBuf, sizeof(btRxBuf));
  loadStore();
  can1.begin();
  can1.setBaudRate(1000000);   // must match the motor
  for (int i = 0; i < 3; i++) {
    BUS[i]->begin();
    BUS[i]->setClock(100000);   // 400 kHz failed on the bench (weak pull-ups, long wires)
  }
  delay(200);
  for (int i = 0; i < 3; i++) { readStatus(i); readAngle(i); }
  lcBegin();
  lastGuiMs = millis();
  info(AUTO_BRAKE ? "Firmware_SOLO_v2 ready (brake engaged, AUTO brake, Bluetooth on Serial5)"
                  : "Firmware_SOLO_v2 ready (brake engaged, MANUAL brake: BRAKE 0 releases it, Bluetooth on Serial5)");
  printParams();
}

void loop() {
  static elapsedMicros ctrlT, encT;
  static elapsedMillis dT, mT, lcT, printT;

  // 1. motor: feedback in, then the fixed-rate control step
  CAN_message_t m;
  while (can1.read(m)) onCan(m);
  if (ctrlT >= CTRL_US) {
    float dt = ctrlT * 1e-6f;
    ctrlT = 0;
    checkFaults(millis());
    control(dt);
  }

  // 2. commands (USB and Bluetooth), brake / height logic
  readGui();
  readBt();
  runSeq();
  safety();
  runHeight();

  // 3. sensors: one short I2C transaction (the ADS1261 runs from its interrupt)
  if (encT >= ENC_STEP_US) { encT = 0; encoderStep(); }

  // 4. telemetry
  if (dT >= TELEM_MS) { dT = 0; sendD(); }
  if (mT >= M_MS) { mT = 0; sendM(); }
  if (lcT >= LC_MS) { lcT = 0; lcOutput(); }
  if (verbose && printT >= 100) { printT = 0; printVerbose(); }
}
