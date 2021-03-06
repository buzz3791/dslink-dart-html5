import "dart:async";
import "dart:html";

import "package:dslink/common.dart";
import "package:dslink/browser_client.dart";
import "package:dslink/responder.dart";
import "package:dslink/src/crypto/pk.dart";

import "package:polymer/polymer.dart";

import "package:paper_elements/paper_dialog.dart";
import "package:paper_elements/paper_input.dart";
import "package:core_elements/core_overlay.dart";

const String DEFAULT_BROKER = "http://127.0.0.1:8080/conn";
const String DEFAULT_NAME = "HTML5";

BrowserECDHLink link;
SimpleNode latitudeNode;
SimpleNode longitudeNode;
SimpleNode headingNode;
SimpleNode altitudeNode;
SimpleNode speedNode;
SimpleNode alphaNode;
SimpleNode betaNode;
SimpleNode gammaNode;
SimpleNode batteryNode;
SimpleNodeProvider provider = new SimpleNodeProvider();

LinkModel model;
PrivateKey key;

CoreOverlay textDisplayOverlay;
ParagraphElement textDisplayText;

main() async {
  var zone = await initPolymer();
  await zone.run(() async {
    await Polymer.onReady;
    await initialize();
    await connect();
  });
}

initialize() async {
  model = new LinkModel();
  AutoBindingElement mainTemplate = querySelector("#main-template");
  mainTemplate.model = model;

  querySelector("#save-button").onClick.listen((x) {
    model.closeSettings();
  });

  textDisplayOverlay = querySelector("#text-display");
  textDisplayText = querySelector("#text");

  var defaultNodes = {
    "Geolocation": {
      "Latitude": {
        r"$type": "number",
        "?value": 0.0
      },
      "Longitude": {
        r"$type": "number",
        "?value": 0.0
      },
      "Heading": {
        r"$type": "number",
        "?value": 0.0
      },
      "Altitude": {
        r"$type": "number",
        "?value": 0.0
      },
      "Speed": {
        r"$type": "number",
        "?value": 0.0
      }
    },
    "Accelerometer": {
      "Alpha": {
        r"$type": "number",
        "?value": 0.0
      },
      "Beta": {
        r"$type": "number",
        "?value": 0.0
      },
      "Gamma": {
        r"$type": "number",
        "?value": 0.0
      }
    },
    "Text_Display": {
      r"$name": "Text Display",
      "Visible": {
        r"$type": "bool",
        r"$writable": "write",
        "?value": false
      },
      "Text_Size": {
        r"$name": "Text Size",
        r"$type": "number",
        r"$writable": "write"
      },
      "Text": {
        r"$name": "Text",
        r"$type": "string",
        r"$writable": "write",
        "?value": ""
      }
    }
  };

  if (window.localStorage.containsKey("dsa_key")) {
    key = new PrivateKey.loadFromString(window.localStorage["dsa_key"]);
  } else {
    key = new PrivateKey.generate();
    window.localStorage["dsa_key"] = key.saveToString();
  }

  if (window.localStorage.containsKey("broker_url")) {
    currentBroker = window.localStorage["broker_url"];
  } else {
    currentBroker = DEFAULT_BROKER;
  }

  if (window.localStorage.containsKey("link_name")) {
    currentName = window.localStorage["link_name"];
  } else {
    currentName = DEFAULT_NAME;
  }

  provider.init(defaultNodes);

  latitudeNode = provider.getNode("/Geolocation/Latitude");
  longitudeNode = provider.getNode("/Geolocation/Longitude");
  headingNode = provider.getNode("/Geolocation/Heading");
  altitudeNode = provider.getNode("/Geolocation/Altitude");
  speedNode = provider.getNode("/Geolocation/Speed");
  alphaNode = provider.getNode("/Accelerometer/Alpha");
  betaNode = provider.getNode("/Accelerometer/Beta");
  gammaNode = provider.getNode("/Accelerometer/Gamma");

  window.navigator.geolocation.watchPosition(
      enableHighAccuracy: true,
      timeout: new Duration(seconds: 60),
      maximumAge: new Duration(seconds: 0)
  ).listen((update) {
    var coords = update.coords;

    latitudeNode.updateValue(coords.latitude);
    longitudeNode.updateValue(coords.longitude);
    headingNode.updateValue(coords.heading);
    altitudeNode.updateValue(coords.altitude);
    speedNode.updateValue(coords.speed);

    model.latitude = coords.latitude.toStringAsFixed(7);
    model.longitude = coords.longitude.toStringAsFixed(7);
    if (coords.heading != null) {
      querySelector("#heading-box").hidden = false;
      model.heading = coords.heading.toStringAsFixed(7);
    } else {
      querySelector("#heading-box").hidden = true;
    }

    if (coords.speed != null) {
      querySelector("#speed-box").hidden = false;
      model.speed = coords.speed.toStringAsFixed(7);
    } else {
      querySelector("#speed-box").hidden = true;
    }
  });

  int lastUpdate = -1;

  window.on["deviceorientation"].listen((DeviceOrientationEvent event) {
    if (lastUpdate != -1 && new DateTime.now().millisecondsSinceEpoch - 300 < lastUpdate) {
      return;
    }

    lastUpdate = new DateTime.now().millisecondsSinceEpoch;

    if (event.alpha != null) {
      alphaNode.updateValue(event.alpha);
      model.alpha = event.alpha.toStringAsFixed(7);
      querySelector("#alpha-box").hidden = false;
    } else {
      querySelector("#alpha-box").hidden = true;
    }

    if (event.beta != null) {
      betaNode.updateValue(event.beta);
      model.beta = event.beta.toStringAsFixed(7);
      querySelector("#beta-box").hidden = false;
    } else {
      querySelector("#beta-box").hidden = true;
    }

    if (event.gamma != null) {
      gammaNode.updateValue(event.gamma);
      model.gamma = event.gamma.toStringAsFixed(7);
      querySelector("#gamma-box").hidden = false;
    } else {
      querySelector("#gamma-box").hidden = true;
    }
  });

  var brokerElement = querySelector("#setting-broker") as PaperInput;
  model.settingBroker = brokerElement;
  if (brokerElement != null) {
    brokerElement.value = currentBroker;
  }
  var nameElement = querySelector("#setting-name") as PaperInput;
  if (nameElement != null) {
    nameElement.value = currentName;
  }
  model.settingName = nameElement;

  provider.getNode("/Text_Display/Visible").subscribe((ValueUpdate update) {
    if (update.value) {
      textDisplayOverlay.open();
    } else {
      textDisplayOverlay.close();
    }
  });

  var textSizeNode = provider.getNode("/Text_Display/Text_Size");
  textSizeNode.subscribe((ValueUpdate update) {
    textDisplayText.style.fontSize = "${update.value}px";
  });
  var fs = textDisplayText.style.fontSize;
  fs = fs.replaceAll("px", "");
  textSizeNode.updateValue(num.parse(fs, (_) => 12));
  provider.getNode("/Text_Display/Text").subscribe((ValueUpdate update) {
    textDisplayText.text = update.value.toString();
  });
}

connect() async {
  if (link != null) {
    link.close();
  }

  link = new BrowserECDHLink(
    currentBroker,
    "${currentName}-",
    key,
    isResponder: true,
    isRequester: false,
    nodeProvider: provider
  );

  link.connect();
}

String currentBroker;
String currentName;

class LinkModel extends Observable {
  @observable
  String latitude = "Unknown";

  @observable
  String longitude = "Unknown";

  @observable
  String heading = "Unknown";

  @observable
  String speed = "Unknown";

  @observable
  String alpha = "Unknown";

  @observable
  String beta = "Unknown";

  @observable
  String gamma = "Unknown";

  void openSettings() {
    dialog = querySelector("#settings-dialog") as PaperDialog;
    dialog.open();
  }

  PaperDialog dialog;
  PaperInput settingName;
  PaperInput settingBroker;

  void closeSettings() {
    dialog.close();

    var broker = settingBroker.value;
    var name = settingName.value;
    if (currentBroker != broker || currentName != name) {
      currentBroker = broker;
      currentName = name;
      window.localStorage["broker_url"] = currentBroker;
      window.localStorage["link_name"] = currentName;
      connect();
    }
  }
}
