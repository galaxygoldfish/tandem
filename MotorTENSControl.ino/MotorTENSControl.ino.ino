#include <Servo.h>
Servo tensServo;

int targetAngle = 0;
int currentAngle = 0;
unsigned long lastStepMs = 0;

// Separate non-blocking intervals for up and down movements
const unsigned long increaseIntervalMs = 15; // Speed going UP (Slower)
const unsigned long decreaseIntervalMs = 2;  // Speed going DOWN (Faster)

void setup() {
  tensServo.write(0);
  tensServo.attach(9);
  Serial.begin(115200);
  delay(1000);
  Serial.println("SYSTEM_START_TENS");
}

void loop() {
  // Always grab the LATEST target; drain any backlog so we never lag.
  while (Serial.available() > 0) {
    int a = Serial.parseInt();
    if (a >= 0 && a <= 180) targetAngle = a;
    // consume trailing newline
    while (Serial.available() > 0 && (Serial.peek() == '\n' || Serial.peek() == '\r')) Serial.read();
  }

  // Determine the current required interval based on direction
  unsigned long currentInterval = (currentAngle < targetAngle) ? increaseIntervalMs : decreaseIntervalMs;

  // Step toward target without blocking, using the dynamically selected interval
  if (currentAngle != targetAngle && millis() - lastStepMs >= currentInterval) {
    lastStepMs = millis();
    currentAngle += (currentAngle < targetAngle) ? 1 : -1;
    tensServo.write(currentAngle);
  }
}