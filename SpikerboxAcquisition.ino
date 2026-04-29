void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println("SYSTEM_START");
}

void loop() {
  int muscleValue = analogRead(A1);
  Serial.print("VALUE:"); 
  Serial.println(muscleValue);
  
  delay(50); // nothing less than 50 otherwise app will not work well
}