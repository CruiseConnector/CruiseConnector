# CruiserConnect – Entwickler-Befehle
# Verwendung: make <befehl>

# Flutter Web lokal starten (kein Xcode nötig)
web-dev:
	flutter run -d chrome --web-port=8080

# Flutter Web Build (für Deployment)
web-build:
	flutter build web --release --web-renderer=canvaskit

# Flutter Web lokal im Netzwerk (für Handy-Tests via WLAN)
web-local:
	flutter run -d web-server --web-port=8080 --web-hostname=0.0.0.0

# Flutter auf Android (normaler Flow)
android:
	flutter run -d android --release

# Flutter auf iOS (normaler Flow)
ios:
	flutter run -d ios

# Tests ausführen
test:
	flutter test

# Analyse
analyze:
	flutter analyze lib/

# Alle Packages holen
setup:
	flutter pub get

# Clean Build
clean:
	flutter clean && flutter pub get

.PHONY: web-dev web-build web-local android ios test analyze setup clean
