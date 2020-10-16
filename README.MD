# Google Analytics 4 Measurement Protocol Client for Apple tvOS
by [Adswerve](https://www.adswerve.com)

Enables Apple TV (tvOS) apps to send Google Analytics events and user properties to "Google Analytics 4" properties (formerly App+Web). Supports both the new  "gtag" and "Firebase" versions of the Measurement Protocol. See Google's [Measurement Protocol](https://developers.google.com/analytics/devguides/collection/protocol/ga4) documentation for more information.

> Warning: This code is based on Google's alpha API and is subject to change. You may encounter breaking changes while it is in alpha. Code using this GA4 MP client should not be pushed to production.

## Implementation
All code needed is in the "GA4MPClient.swift" file. Add this file to your project and update the following "GA Configuration" properties based on your needs:

* To send data to a Google Analytics **_web stream_** using the gtag flavor of the protocol:
  * Set **useProtocolVersion = .gtag**
  * **apiSecret**: Enter the Measurement Protocol API secret for your web stream
  * **measurementId**: Enter the [Measurement ID](https://developers.google.com/analytics/devguides/collection/protocol/ga4/sending-events?client_type=gtag#required_parameters) for your web stream

* To send data to a Google Analytics (Firebase) **_app stream_** using the Firebase flavor of the protocol:
  * Set **useProtocolVersion = .firebase**
  * **apiSecret**: Enter the Measurement Protocol API secret for your app stream
  * **firebaseAppId**: Enter the [Firebase App ID](https://developers.google.com/analytics/devguides/collection/protocol/ga4/sending-events?client_type=firebase#required_parameters) for your Firebase app stream

API secrets and IDs can be found in Google Analytics under **Admin** > **Data Streams**.

## Usage

The API of this client is modeled after the [Firebase Analytics SDK](https://firebase.google.com/docs/reference/swift/firebaseanalytics/api/reference/Classes/Analytics), so if you are familiar with logging events or setting user properties with Firebase, using this client should be a no brainer.

##### Create a reference to the shared client instance:
```
let mpClient = GA4MPClient.shared
```

##### To log an event:

* An event with parameters
```
mpClient.logEvent("my_event", ["my_first_parameter": "foo", "my_second_parameter": "bar"], "another_parameter": 42)
```
* An event with no parameters:
```
mpClient.logEvent("my_other_event", nil)
```

##### To set default event parameters that will be included on all subsequent events:
```
mpClient.setDefaultEventParameters(["my_first_default": "blah", "my_second_default": "meh"])
```
_Note: All default event parameters are persisted into the future via UserDefaults._

##### To remove a default event parameter pass NSNull() as the value of the parameter:
```
mpClient.setDefaultEventParameters(["my_first_default": NSNull()])
```

##### To clear ALL default event parameters pass nil:
```
mpClient.setDefaultEventParameters(nil)
```

##### To set a user property:
```
mpClient.setUserProperty("the new value", forName: "my_property")
```
_Note: User properties are persisted into the future via UserDefaults and sent in subsequent event payloads unless cleared._

##### To clear a user property pass nil:
```
mpClient.setUserProperty(nil, forName: "my_property")
```

##### To set the User ID:
```
mpClient.setUserID("UNIQUE_BACKEND_USER_ID_HERE")
```
_Note: The User ID is persisted into the future via UserDefaults; however, it is only included in event payloads when the user is logged in._

##### To clear the User ID pass nil:
```
mpClient.setUserID(nil)
```

##### To indicate that the user is logged in:
```
mpClient.setUserLoggedIn(true)
```
_Note: Logged in state is intentionally not stored in a persistent fashion. Users will default to logged out status each time the client is instantiated unless you reassert that they are still logged in._

##### To indicate that the user has logged out (or otherwise lost authentication):
```
mpClient.setUserLoggedIn(false)
```

##### By default, when the client is first instantiated a random UUID is generated and used as the Client ID/App Instance ID on the assumption that the device will need a unique ID. To provide a different ID (e.g., a Firebase app instance ID from an actual app or a GA client ID from a web page):
```
mpClient.setDeviceID("UNIQUE_ID_HERE")
```

##### By default, analytics collection is enabled. To disable analytics collection:
```
mpClient.setAnalyticsCollectionEnabled(false)
```

##### By default, non-personalized ads is enabled. To disable non-personalized ads:
```
mpClient.setNonPersonalizedAds(false)
```

##### To clear all analytics data from the client and reset the device ID:
```
mpClient.resetAnalyticsData()
```

## Debugging

To aid debugging during development:

* Enable **debugMode** to turn on logging and validate events and user properties against [GA4 rules](https://support.google.com/analytics/answer/9267744). Any validation errors will be logged to the Xcode console.
```
mpClient.debugMode = true
```
* Enable **throwOnValidationErrorsInDebug** to throw IllegalArgument exceptions if any validation fails. (Only applies if debugMode is enabled.)
```
mpClient.throwOnValidationErrorsInDebug = true
```
* Enable **useValidationEndpoint** to send hits to GA's validation server instead of to your GA property. Responses from the GA server will be logged to the Xcode console and will include feedback if errors are detected.
```
mpClient.useValidationEndpoint = true
```

## Limitations
As noted above, this code is based on Google's alpha release. Things will change, and break, but at least we can get the ball rolling.

Here are a few known limitations:
* Firebase's ["automatic" events](https://support.google.com/firebase/answer/6317485) are currently reserved and will be rejected by the GA server when sent via Measurement Protocol. This makes it impossible to log a **screen_view** event, or a **session_start**, etc.
* There are currently only two flavors of the protocol: Firebase ("app") and gtag ("web"). Events sent with the Firebase flavor show up in BigQuery as `device.category = mobile` and `platform = ios` (or `android`) depending on how the app stream is configured. Events sent with the gtag flavor show up in BigQuery as `device.category = desktop` and `platform = web`. Clearly there will be a need to embrace other types of connected devices that fall outside the current definitions of "app" and "web" -- like, say, connected TVs, or refrigerators -- but for now we have to make do.
* While the new Measurement Protocol spec allows multiple events to be uploaded together in one payload, the current version of this client sends events individually, immediately after logEvent() is called.
* DebugView is not currently supported.
* While initial testing indicates that data appears in the GA UI and in BigQuery as expected, initial design assumptions may prove incorrect, documentation may have been misunderstood, and/or reality may change. YMMV. Use with your eyes open and let us know if anything seems to fly counter to your expectations!

## Meta
Created by Adswerve, Inc. and distributed under the BSD 3-Clause license. See `LICENSE` for more information.
Ping us on [#measure](https://measure.slack.com/) if you have questions, suggestions, or notice anything distinctly problematic.

## Release History

* 0.1.0
  * Initial version based on Google's 10/15/20 alpha release.
