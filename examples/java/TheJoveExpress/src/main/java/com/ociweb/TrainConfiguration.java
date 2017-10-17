package com.ociweb;

import com.ociweb.gl.api.ArgumentProvider;
import com.ociweb.iot.maker.TriState;
import com.ociweb.model.ActuatorDriverPort;
import com.ociweb.iot.maker.Port;

import static com.ociweb.iot.maker.Port.*;

public class TrainConfiguration  {

    final String trainName;

    final boolean mqttDefaultLocal = false;
    final boolean mqttEnabled = true;
    final String mqttBroker;
    final String mqttClientName;
    final int mqttPort = 1883;

    final TriState telemetryEnabled;
    final String telemetryHost = null;

    final boolean lifecycleEnabled = true;

    final boolean engineEnabled = true;
    final ActuatorDriverPort engineAccuatorPort = ActuatorDriverPort.A;

    final boolean lightsEnabled = true;
    final int lightDetectFreq = 250;
    final Port lightSensorPort = A0;
    final ActuatorDriverPort lightAccuatorPort = ActuatorDriverPort.B;

    final boolean billboardEnabled = false;
    final boolean cameraEnabled = false;

    final boolean locationEnabled = true;
    final int headingReadFreq = 250;

    final boolean appServerEnabled = false;
    final int appServerPort = 8089;

    final boolean soundEnabled = false;
    final Port piezoPort = A1;

    TrainConfiguration(ArgumentProvider args) {
        this.trainName = args.getArgumentValue("--name", "-n", "thejoveexpress");
        String localHostName = mqttDefaultLocal ? "localhost" : this.trainName + ".local";
        this.mqttBroker = args.getArgumentValue("--broker", "-b", localHostName);
        this.mqttClientName = trainName;
        this.telemetryEnabled = Enum.valueOf(TriState.class, args.getArgumentValue("--telemetry", "-t", "latent"));
    }
}
