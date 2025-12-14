#include <SoftwareSerial.h>
#include "Adafruit_BluefruitLE_UART.h"
#include <HX711_ADC.h>  // Librería para manejar el módulo amplificador de celda de carga HX711

// Pines HX711
const int HX711_dout = 3;  // Pin DT (data)
const int HX711_sck = 4;   // Pin SCK (clock)

// Objeto HX711 (creamos una instancia de la clase HX711_ADC)
HX711_ADC LoadCell(HX711_dout, HX711_sck);

// COMMON SETTINGS BLE
#define BLUEFRUIT_UART_RTS_PIN -1   // No usado
#define BLUEFRUIT_UART_CTS_PIN 11   // CTS (opcional)
#define BLUEFRUIT_SWUART_RXD 8      // Arduino RX <- Bluefruit TXO
#define BLUEFRUIT_SWUART_TXD 9      // Arduino TX -> Bluefruit RXI
#define BLUEFRUIT_UART_MODE_PIN 12  // No usado en UART Friend

#define BUFSIZE 160  // Size of the read buffer for incoming data
#define FACTORYRESET_ENABLE 0
#define VERBOSE_MODE true

// Objeto BLE
SoftwareSerial bluefruitSS = SoftwareSerial(BLUEFRUIT_SWUART_RXD, BLUEFRUIT_SWUART_TXD);
Adafruit_BluefruitLE_UART ble(bluefruitSS, BLUEFRUIT_UART_MODE_PIN,
                              BLUEFRUIT_UART_CTS_PIN, BLUEFRUIT_UART_RTS_PIN);

// A small helper
void error(const __FlashStringHelper* err) {
  Serial.println(err);
  while (1)
    ;
}

// Variables globales
unsigned long t = 0;          // Variable de tiempo para controlar intervalos de lectura
float calibracion = 154.40;  // Factor de calibración inicial
float tiempoEnvio = 0.0;

void setup() {
  // Initialize Serial for debug
  while (!Serial);
  delay(500);

  Serial.begin(115200);

  // Setup HX711
  Serial.println("Iniciando HX711...");
  LoadCell.begin();
  long stabilizingtime = 2000;
  boolean _tare = true;
  LoadCell.start(stabilizingtime, _tare);

  if (LoadCell.getTareTimeoutFlag()) {
    Serial.println("ERROR: HX711 no responde");
    while (1);
  } else {
    Serial.println("HX711 listo");
  }
  LoadCell.setCalFactor(calibracion);  // Establece un factor de calibración inicial

  // Initialize Bluefruit
  Serial.println(F("======================================"));
  Serial.println(F("Adafruit Bluefruit Sensor de Peso"));
  Serial.println(F("======================================"));
  Serial.println();
  Serial.print(F("Initializing Bluefruit LE UART Friend... "));

  if (!ble.begin(VERBOSE_MODE)) {
    error(F("Couldn't find Bluefruit, make sure it's in CoMmanD mode & check wiring?"));
  }
  Serial.println(F("OK!"));

  ble.echo(false);

  Serial.println("Requesting Bluefruit info:");
  ble.info();

  Serial.println(F("Esperando conexión BLE... "));
  Serial.println();

  ble.verbose(false);

  /* Wait for connection */
  while (!ble.isConnected()) {
    Serial.print(F("."));
    delay(500);
  }

  delay(3000);

  Serial.println(F("\n******************************"));
  // Set module to DATA mode
  Serial.println(F("Conectado!"));
  ble.setMode(BLUEFRUIT_MODE_DATA);

  Serial.println(F("******************************"));
}

void loop() {
  String Strcommand = "";
  LoadCell.update();

  if (millis() - tiempoEnvio >= 1000) {
    float peso = LoadCell.getData();
    if (peso < 0.0) {
      peso = 0.0;
    }
    ble.print(peso);
    Serial.print("Enviado: ");
    Serial.println(peso);
    tiempoEnvio = millis();
  }

  while (Serial.available() > 0) {
    char comm = Serial.read();
    Strcommand += (char)comm;
  }

  while (ble.available() > 0) {
    int c = ble.read();
    Strcommand += (char)c;
  }

  if (Strcommand.length() > 0) {
    processCommand(Strcommand);
  }
}


void processCommand(String command) {
  Serial.print("Entra en process: ");
  Serial.println(command);
  if (command == "T") {
    // Realizar tara
    LoadCell.tareNoDelay();

    // Espera hasta que el proceso de tara termine
    while (!LoadCell.getTareStatus()) {
      LoadCell.update();  // Debe actualizarse constantemente
    }
    Serial.println("Tara realizada");

  } else if (command == "C") {
    // Calibración
    calibrarPeso();

  } else {
    return;
  }
}

void calibrarPeso() {
  //  -----------  Tara -----------
  LoadCell.tareNoDelay();  // Inicia el proceso de tara (poner a cero)

  // Espera hasta que el proceso de tara termine
  while (!LoadCell.getTareStatus()) {
    LoadCell.update();  // Debe actualizarse constantemente
  }
  delay(500);         // permitir estabilización después de la tara
  LoadCell.update();  // Mantiene actualizada la lectura
  delay(10);          // Pequeño retardo para no saturar el bucle

  // -----------  Peso conocido  -----------
  Serial.println("Introduzca peso conocido: ");
  Serial.flush();
  String input = "";
  Serial.read();  // Limpia el buffer inicial

  while (true) {
    if (Serial.available() > 0) {
      char c = Serial.read();
      if (c == '\n') {  // Fin de línea indica que se terminó de escribir
        break;
      }
      input += c;  // Acumula caracteres del número
    }
    delay(10);
  }

  float pesoConocido = input.toFloat();  // Convierte la entrada en número
  delay(100);

  // Calcula el nuevo factor de calibración con el peso conocido

  LoadCell.update();

  // Tomar varias lecturas para mayor precisión
  unsigned long tiempoInicio = millis();

  // Tiempo de espera para la calibración

  Serial.println("Calibrando...");
  while (millis() - tiempoInicio < 2000) {

    LoadCell.update();
    delay(100);
  }

  // Aplica y calcula el nuevo factor de calibración
  float nuevoCalFactor = LoadCell.getNewCalibration(pesoConocido);
  Serial.println(nuevoCalFactor);
  Serial.println("Calibrado!");

  LoadCell.update();
}
