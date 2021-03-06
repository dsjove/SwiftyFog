package com.ociweb;

import com.ociweb.behaviors.*;
import com.ociweb.behaviors.internal.AccelerometerBehavior;
import com.ociweb.behaviors.internal.ActuatorDriverBehavior;
import com.ociweb.gl.api.MQTTBridge;
import com.ociweb.gl.api.MQTTQoS;
import com.ociweb.iot.grove.simple_analog.SimpleAnalogTwig;
import com.ociweb.iot.grove.six_axis_accelerometer.SixAxisAccelerometerTwig;
import com.ociweb.iot.maker.*;
import com.ociweb.model.PubSub;
import com.ociweb.pronghorn.iot.i2c.I2CJFFIStage;

import static com.ociweb.iot.grove.motor_driver.MotorDriverTwig.MotorDriver;
import static com.ociweb.iot.grove.oled.OLEDTwig.OLED_128x64;
import static com.ociweb.iot.grove.oled.OLEDTwig.OLED_96x96;

public class TheJoveExpress implements FogApp
{
    private TrainConfiguration config;
    private MQTTBridge mqttBridge;

    @Override
    public void declareConnections(Hardware hardware) {
        config = new TrainConfiguration(hardware);
        
        hardware.setDefaultRate(16_000_000);
        
        I2CJFFIStage.debugCommands = false;

        if (config.mqttEnabled) {
            this.mqttBridge = hardware.useMQTT(config.mqttBroker, config.mqttPort, config.mqttClientName, 40, 20000)
                    .cleanSession(true)
                    .keepAliveSeconds(10);
        }
        if (config.appServerEnabled) hardware.useHTTP1xServer(config.appServerPort); // TODO: heap problem on Pi0
        if (config.lightsEnabled) hardware.connect(SimpleAnalogTwig.LightSensor, config.lightSensorPort, config.lightDetectFreq);
        if (config.soundEnabled) hardware.useSerial(Baud.B_____9600);
        if (config.engineEnabled || config.lightsEnabled) hardware.connect(MotorDriver);
        if (config.billboardEnabled) hardware.connect(OLED_128x64);/*c.connect(OLED_96x96);*/
 //       if (config.faultDetectionEnabled) hardware.connect(SixAxisAccelerometerTwig.SixAxisAccelerometer.readAccel, config.accelerometerReadFreq);
        if (config.cameraEnabled) ; //c.connect(pi-bus camera);
        if (config.soundEnabled) ; //c.connect(serial mp3 player);

        // TODO: move this logic into Hardware
        switch (config.telemetryEnabled) {
            case on:
                if (config.telemetryHost != null) {
                    hardware.enableTelemetry(config.telemetryHost);
                }
                else {
                    hardware.enableTelemetry();
                }
                break;
            case latent:
                if (hardware.isTestHardware()) {
                    if (config.telemetryHost != null) {
                        hardware.enableTelemetry(config.telemetryHost);
                    }
                    else {
                        hardware.enableTelemetry();
                    }
                }
                break;
        }

        if (config.lightsEnabled) {
            hardware.setTimerPulseRate(1000);
        }
    }

    public void declareBehavior(FogRuntime runtime) {
        PubSub pubSub = new PubSub(config.trainName, runtime, config.mqttEnabled ? mqttBridge : null);

        if (config.lifecycleEnabled) {
            final String lifeCycleFeedback = "lifecycle/feedback";
            final String internalMqttConnect = "MQTT/Connection";
            final String shutdownControl = "lifecycle/control/shutdown";
            pubSub.lastWill(lifeCycleFeedback, true, MQTTQoS.atLeastOnce, blobWriter -> blobWriter.writeBoolean(false)); // TODO remove immutable check
            pubSub.connectionFeedbackTopic(internalMqttConnect);
            LifeCycleBehavior lifeCycle = new LifeCycleBehavior(runtime,
                    pubSub.publish(lifeCycleFeedback, true, MQTTQoS.atLeastOnce));
            pubSub.subscribe(lifeCycle, internalMqttConnect, MQTTQoS.atLeastOnce, lifeCycle::onMQTTConnect);
            pubSub.subscribe(lifeCycle, shutdownControl, MQTTQoS.atMostOnce, lifeCycle::onShutdown);
        }

        final String allFeedback = "feedback";
        final String accelerometerInternal = "accelerometer/internal";
        final String engineState = "engine/state/feedback";
        final String faultFeedback = "fault/feedback";
        final String lightsPowerFeedback = "lights/power/feedback";

        if (config.engineEnabled || config.lightsEnabled) {
            final String actuatorPowerInternal = "actuator/power/internal";

            final ActuatorDriverBehavior actuator = new ActuatorDriverBehavior(runtime);
            pubSub.subscribe(actuator, actuatorPowerInternal, actuator::setPower);

            if (config.engineEnabled) {
                final EngineBehavior engine = new EngineBehavior(runtime, actuatorPowerInternal, config.engineActuatorPort,
                        pubSub.publish("engine/power/feedback", false, MQTTQoS.atMostOnce),
                        pubSub.publish("engine/calibration/feedback", false, MQTTQoS.atMostOnce),
                        pubSub.publish("engine/state/feedback", false, MQTTQoS.atMostOnce));
                pubSub.subscribe(engine, allFeedback, MQTTQoS.atMostOnce, engine::onAllFeedback);
                pubSub.subscribe(engine, "engine/power/control", MQTTQoS.atMostOnce, engine::onPower);
                pubSub.subscribe(engine, "engine/calibration/control", MQTTQoS.atMostOnce, engine::onCalibration);
                pubSub.subscribe(engine, faultFeedback, engine::onFault);
            }

            if (config.lightsEnabled) {
                final String lightsAmbientFeedback = "lights/ambient/feedback";
                final AmbientLightBehavior ambientLight = new AmbientLightBehavior(runtime, config.lightSensorPort,
                        pubSub.publish(lightsAmbientFeedback, false, MQTTQoS.atMostOnce));
                pubSub.subscribe(ambientLight, allFeedback, MQTTQoS.atMostOnce, ambientLight::onAllFeedback);

                final LightingBehavior lights = new LightingBehavior(runtime, actuatorPowerInternal, config.lightActuatorPort,
                        pubSub.publish("lights/override/feedback", false, MQTTQoS.atMostOnce),
                        pubSub.publish(lightsPowerFeedback, false, MQTTQoS.atMostOnce),
                        pubSub.publish("lights/calibration/feedback", false, MQTTQoS.atMostOnce));
                pubSub.subscribe(lights, allFeedback, MQTTQoS.atMostOnce, lights::onAllFeedback);
                pubSub.subscribe(lights, "lights/override/control", MQTTQoS.atMostOnce, lights::onOverride);
                pubSub.subscribe(lights, "lights/calibration/control", MQTTQoS.atMostOnce, lights::onCalibration);
                pubSub.subscribe(lights, lightsAmbientFeedback, lights::onDetected);
            }
        }
        if (config.faultDetectionEnabled) {
//            final AccelerometerBehavior accelerometerBehavior = new AccelerometerBehavior(runtime, accelerometerInternal);
//            pubSub.registerBehavior(accelerometerBehavior);
        }

        if (config.faultDetectionEnabled) {
            final MotionFaultBehavior motionFault = new MotionFaultBehavior(runtime,
                    pubSub.publish(faultFeedback, false, MQTTQoS.atMostOnce));
            pubSub.subscribe(motionFault, allFeedback, MQTTQoS.atMostOnce, motionFault::onAllFeedback);
            pubSub.subscribe(motionFault, "fault/control", MQTTQoS.atMostOnce, motionFault::onForceFault);
            pubSub.subscribe(motionFault, accelerometerInternal, motionFault::onAccelerometer);
            pubSub.subscribe(motionFault, engineState, motionFault::onEngineState);
        }

        if (config.billboardEnabled) {
            final TextDisplay billboard = new TextDisplay(runtime,
                    pubSub.publish("billboard/text/feedback", false, MQTTQoS.atMostOnce));
            pubSub.subscribe(billboard, allFeedback, MQTTQoS.atMostOnce, billboard::onAllFeedback);
            pubSub.subscribe(billboard, "billboard/text/control", MQTTQoS.atMostOnce, billboard::onText);
            pubSub.subscribe(billboard, lightsPowerFeedback, billboard::onLightsPower);
            /*
            final BillboardBehavior billboard = new BillboardBehavior(runtime,
                    pubSub.publish("billboard/spec/feedback", true, MQTTQoS.atMostOnce));
            pubSub.subscribe(billboard, allFeedback, MQTTQoS.atMostOnce, billboard::onAllFeedback);
            pubSub.subscribe(billboard, "billboard/image/control", MQTTQoS.atMostOnce, billboard::onImage);
            */
        }

        if (config.cameraEnabled) {
            // mqtt inbound to take picture
            // save for web app server
            // runtime.registerListener(new CameraBehavior(runtime));
        }

        if (config.soundEnabled) {
//                final String soundPiezoControl = "sound/piezo/control";
//                final SoundBehavior sound = new SoundBehavior(runtime, config.piezoPort);
//                if (config.mqttEnabled) {
//                    runtime.bridgeSubscription(soundPiezoControl, prefix + soundPiezoControl, mqttBridge).setQoS(MQTTQoS.atMostOnce);
//                }
//                runtime.registerListener(sound)
//                        .addSubscription(soundPiezoControl, sound::onLevel);
            // MQTT outbound with sound file listing
            // MQTT outbound with play status
            // MQTT inbound with play/stop/pause commands
            // runtime.registerListener(new SoundBehavior(runtime));
        }

        if (config.appServerEnabled) {
            runtime.addFileServer("").includeAllRoutes(); // TODO: use resource folder
        }

        pubSub.finish();
    }
}
