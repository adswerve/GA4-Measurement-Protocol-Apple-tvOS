//
//  GA4MPClient.swift
//
//  Sends events and user properties to Google Analytics using the GA4 (App+Web)
//  Measurement Protocol as defined in
//  https://developers.google.com/analytics/devguides/collection/protocol/ga4/
//
//  Public methods are modeled after the Firebase Analytics API and are subject to the
//  same configuration limits. See https://support.google.com/analytics/answer/9267744.
//
//  Supports both the "Firebase" and "gtag" versions of the GA4 Measurement Protocol.
//
//  By default:
//    - The "gtag" flavor is used, which requires that you provide the API Secret and
//      Measurement ID for the appropriate web stream. To use the "Firebase" flavor, set
//      useProtocolVersion = .firebase and provide the API Secret and Firebase App ID
//      for the appropriate app stream.
//    - Analytics collection is enabled. To disable it, call setAnalyticsCollectionEnabled(false).
//    - nonPersonalizedAds is enabled. To disable it, call setNonPersonalizedAds(false).
//    - A random UUID is used for the device ID. Use setDeviceId(_:) to provide a different
//      value (e.g., an app instance ID supplied by an app, or cliend ID from a web page).
//
//  Other notes:
//    - User properties, User ID, and default event parameters are persisted into the future
//      via UserDefaults unless cleared.
//    - User ID is only sent to GA when the user is logged in via setUserLoggedIn(true).
//    - Logged in state is intentionally not stored in a persistent fashion. The user will
//      default to logged out status each time this client is instantiated unless you
//      reassert that the user is still logged in.
//
//  To aid development/debugging:
//    - Set debugMode = true to enable logging and validation against GA4 rules.
//    - Set throwOnValidationErrorsInDebug = true to throw exceptions if validation fails.
//    - Set useValidationEndpoint = true to send hits to GA's validation server instead
//      of your GA property (responses from server will include feedback and be logged).
//
//  Created by Chris Hubbard and Charles Farina on 10/14/20.
//  Copyright © 2020 Adswerve. All rights reserved.
//

import Foundation

class GA4MPClient {
    
    // MARK: - GA configuration
    
    private let useProtocolVersion : protocolVersion = .gtag
    private let apiSecret = "YOUR_SECRET_HERE" // required
    private let measurementID = "YOUR_MEASUREMENT_ID_HERE" // required for gtag protocol
    private let firebaseAppID = "YOUR_FIREBASE_APP_ID_HERE" // required for Firebase protocol
    
    // MARK: - Measurement protocol endpoints
    
    private let endPointProduction = "https://www.google-analytics.com/mp/collect"
    private let endPointValidation = "https://www.google-analytics.com/debug/mp/collect"
    
    // MARK: - UserDefaults keys
    
    private let defaultsKeyAnalyticsCollectionEnabled = "mpv2_analytics_enabled"
    private let defaultsKeyNonPersonalizedAds = "mpv2_non_personalized_ads"
    private let defaultsKeyDeviceID = "mpv2_device_id"
    private let defaultsKeyUserID = "mpv2_user_id"
    private let defaultsKeyDefaultParameters = "mpv2_default_parameters"
    private let defaultsKeyUserProperties = "mpv2_user_properties"
    
    // MARK: - Validation rules
    // Per: https://support.google.com/analytics/answer/9267744
    
    private let validationRuleEventMaxParameters = 25
    private let validationRuleEventNameMaxLength = 40
    private let validationRuleParameterNameMaxLength = 40
    private let validationRuleParameterValueMaxLength = 100
    private let validationRuleUserPropertyMaxCount = 25
    private let validationRuleUserPropertyNameMaxLength = 24
    private let validationRuleUserPropertyValueMaxLength = 36
    private let validationRuleUserIDValueMaxLength = 256
    private let validationRuleEventNamePattern = "^(?!ga_|google_|firebase_)[A-Za-z]{1}[A-Za-z0-9_]{0,%d}$"
    private let validationRuleParameterNamePattern = "^(?!ga_|google_|firebase_)[A-Za-z]{1}[A-Za-z0-9_]{0,%d}$"
    private let validationRuleUserPropertyNamePattern = "^(?!ga_|google_|firebase_)[A-Za-z]{1}[A-Za-z0-9_]{0,%d}$"
    private var validationRegexEventName: NSRegularExpression?
    private var validationRegexParameterName: NSRegularExpression?
    private var validationRegexUserPropertyName: NSRegularExpression?
    
    // MARK: - Public properties
    
    /// The shared singleton client object.
    static let shared = GA4MPClient()
    /// Set true to enable debug logging and validation
    var debugMode = false
    /// Set true to throw NSInvalidArgumentException on validation errors (when debugMode is enabled). Default is false.
    var throwOnValidationErrorsInDebug = false
    /// Set true to send events to GA's validation server and log responses. Default is false.
    var useValidationEndpoint = false
    
    // MARK: - Private properties
    
    /// Measurement Protocol versions supported.
    private enum protocolVersion { case gtag, firebase }
    /// Unique ID for this device. Used as Client ID (gtag) or App Instance ID (Firebase). May be overridden by calling setDeviceId(_:).
    private var deviceID: String = ""
    /// Flag indicating whether analytics data should be sent to GA. Set by setAnalyticsCollectionEnabled(_:).
    private var analyticsCollectionEnabled = true
    /// Flag indicating whether nonPersonalizedAds is enabled. Set by setNonPersonalizedAds(_:).
    private var nonPersonalizedAds : Bool = true
    /// Unique backend (authenticated) user ID for the current user. Set by setUserID(_:).
    private var userID: String? = nil
    /// Flag indicating whether user is logged in to enable user ID to be sent. Set by setUserLoggedIn(_:).
    private var userIsLoggedIn = false
    /// Optional default parameters to be included on every event. Set by setDefaultEventParameters(_:).
    private var defaultParameters: [String : Any]? = nil
    /// User properties to be sent to GA. Set by setUserProperty(_:forName:) and cleared once sent to GA.
    private var userProperties: [String : Any]? = nil
    /// Queue to ensure thread safety in multi-thread environments.
    private let queue = DispatchQueue(label: "GA4MPClient-queue", attributes: .concurrent)
    
    // MARK: - Initializer
    
    private init() {
        debugLog("Initializing GA4MPClient...")
        // restore (or generate) unique device ID
        if let storedDeviceID = UserDefaults.standard.string(forKey: defaultsKeyDeviceID) {
            deviceID = storedDeviceID
            debugLog("Restoring device ID: " + storedDeviceID)
        } else {
            deviceID = NSUUID().uuidString
            UserDefaults.standard.set(deviceID, forKey: defaultsKeyDeviceID)
            debugLog("Storing device ID: " + deviceID)
        }
        // restore User ID
        if let storedUserID = UserDefaults.standard.string(forKey: defaultsKeyUserID) {
            userID = storedUserID
            debugLog("Restoring user ID: " + storedUserID)
        }
        // restore user properties
        if let storedUserProperties = UserDefaults.standard.dictionary(forKey: defaultsKeyUserProperties) {
            userProperties = storedUserProperties
            debugLog("Restoring user properties: " + storedUserProperties.description)
        }
        // restore default event parameters
        if let storedParameters = UserDefaults.standard.dictionary(forKey: defaultsKeyDefaultParameters) {
            defaultParameters = storedParameters
            debugLog("Restoring default event parameters: " + storedParameters.description)
        }
        // restore analyticsCollectionEnabled setting
        if let storedValue = UserDefaults.standard.string(forKey: defaultsKeyAnalyticsCollectionEnabled),
           let enabled = Bool(storedValue) {
            analyticsCollectionEnabled = enabled
            debugLog("Restoring analyticsCollectionEnabled: " + String(enabled))
        }
        // restore nonPersonalizedAds setting
        if let storedValue = UserDefaults.standard.string(forKey: defaultsKeyNonPersonalizedAds),
           let enabled = Bool(storedValue) {
            nonPersonalizedAds = enabled
            debugLog("Restoring nonPersonalizedAds: " + String(enabled))
        }
        // set validation patterns
        validationRegexEventName = makeEventNameRegex()
        validationRegexParameterName = makeParameterNameRegex()
        validationRegexUserPropertyName = makeUserPropertyNameRegex()
    }
    
    // MARK: - Public methods
    
    /// Sets whether analytics collection is enabled for this client on this device. This setting is persisted across app sessions. By default it is enabled.
    ///
    /// - Parameter analyticsCollectionEnabled: Pass true to enable analytics collection.
    func setAnalyticsCollectionEnabled(_ analyticsCollectionEnabled: Bool) {
        queue.async(flags: .barrier) {
            self.analyticsCollectionEnabled = analyticsCollectionEnabled
            UserDefaults.standard.setValue(String(analyticsCollectionEnabled), forKey: self.defaultsKeyAnalyticsCollectionEnabled)
            self.debugLog("Analytics collection " + (analyticsCollectionEnabled ? "enabled" : "disabled"))
        }
    }
    
    /// Overrides the default (random) device ID. Use this method to set a specific device ID, if needed.
    ///
    /// - Parameter deviceId: The unique device ID to use going forward.
    func setDeviceID(_ deviceId: String) {
        queue.async(flags: .barrier) {
            self.deviceID = deviceId
            UserDefaults.standard.setValue(deviceId, forKey: self.defaultsKeyDeviceID)
            self.debugLog("Set device ID: " + deviceId)
        }
    }
    
    /// Sets whether events can be used for personalized advertising purposes. This setting is persisted across app sessions. By default this is disabled.
    ///
    /// Note that this controls the "nonPersonalizedAds" field on event uploads, and as such is inverted:
    /// nonPersonalizedAds = true means that events CANNOT be used for personalizing ads.
    ///
    /// - Parameter nonPersonalizedAds: Pass false disable nonPersonalizedAds.
    func setNonPersonalizedAds(_ nonPersonalizedAds: Bool) {
        queue.async(flags: .barrier) {
            self.nonPersonalizedAds = nonPersonalizedAds
            UserDefaults.standard.setValue(String(nonPersonalizedAds), forKey: self.defaultsKeyNonPersonalizedAds)
            self.debugLog("Non-personalized ads " + (nonPersonalizedAds ? "enabled" : "disabled"))
        }
    }
    
    /// Sets whether user is logged in (authenticated). User ID is only sent to GA when user is logged in.
    ///
    /// This setting is not perstisted so users will default to "logged out" state each time this client is instantiated.
    ///
    /// - Parameter loggedIn: Pass true when the user logs in. False when the user logs out.
    func setUserLoggedIn(_ loggedIn: Bool) {
        queue.async(flags: .barrier) {
            self.userIsLoggedIn = loggedIn
            self.debugLog("User is " + (loggedIn ? "logged in" : "logged out"))
        }
    }
    
    /// Sets a user property to a given value. Up to 25 user property names are supported. Once set, user property values
    /// persist throughout the app lifecycle and across sessions.
    ///
    /// - Parameters:
    ///   - value: The value of the user property. Values can be up to 36 characters long. Setting the
    ///       value to nil removes the user property.
    ///   - name: The name of the user property to set. Should contain 1 to 24 alphanumeric characters or underscores
    ///       and must start with an alphabetic character. The "firebase_", "google_", and "ga_" prefixes are reserved
    ///       and should not be used for user property names.
    func setUserProperty(_ value: String?, forName name: String) {
        queue.async(flags: .barrier) {
            self.debugLog("Set user property: name, value: \(name), " + (value ?? "nil"))
            let newUserProperties = NSMutableDictionary()
            if let currentUserProperties = self.userProperties {
                newUserProperties.setDictionary(currentUserProperties)
            }
            if (nil == value) {
                newUserProperties.removeObject(forKey: name)
            } else {
                newUserProperties.addEntries(from: [name : value!])
            }
            self.userProperties = newUserProperties.count > 0 ? newUserProperties as? [String : Any] : nil
            self.validateUserProperty(value, forName: name) // check after update so count is current
            if (nil == self.userProperties) {
                UserDefaults.standard.removeObject(forKey: self.defaultsKeyUserProperties)
            } else {
                UserDefaults.standard.setValue(self.userProperties, forKey: self.defaultsKeyUserProperties)
            }
        }
    }
    
    /// Sets the user ID property. This feature must be used in accordance with Google's Privacy Policy at
    /// https://www.google.com/policies/privacy.
    ///
    /// - Parameter userID: The user ID to ascribe to the user of this app on this device, which must be
    ///     non-empty and no more than 256 characters long. Setting userID to nil removes the user ID.
    func setUserID(_ userID : String?) {
        queue.async(flags: .barrier) {
            self.debugLog("Set User ID: " + (userID ?? "nil"))
            self.userID = userID
            if (nil == userID) {
                UserDefaults.standard.removeObject(forKey: self.defaultsKeyUserID)
            } else {
                self.validateUserID(userID)
                UserDefaults.standard.setValue(userID, forKey: self.defaultsKeyUserID)
            }
        }
    }
    
    /// Adds parameters that will be set on every event logged from this client. The values passed in the parameters
    /// dictionary will be added to the dictionary of default event parameters. These parameters persist across app
    /// runs. They are of lower precedence than event parameters, so if an event parameter and a parameter set
    /// using this API have the same name, the value of the event parameter will be used. The same limitations
    /// on event parameters apply to default event parameters.
    ///
    /// - Parameter parameters: Parameters to be added to the dictionary of parameters added to every
    ///     event. They will be added to the dictionary of default event parameters, replacing any existing parameter
    ///     with the same name. Valid parameters are NSString and NSNumber (signed 64-bit integer and 64-bit
    ///     floating-point number). Setting a key's value to NSNull() will clear that parameter. Passing in a nil
    ///     dictionary will clear all parameters.
    func setDefaultEventParameters(_ parameters: [String : Any]?) {
        queue.async(flags: .barrier) {
            guard nil != parameters else {
                self.defaultParameters = nil
                UserDefaults.standard.removeObject(forKey: self.defaultsKeyDefaultParameters)
                self.debugLog("Cleared default event parameters")
                return
            }
            self.validateParameters(source: #function, parameters: parameters)
            let newDefaults = NSMutableDictionary()
            if let currentDefaults = self.defaultParameters {
                newDefaults.setDictionary(currentDefaults)
            }
            for (name, value) in parameters! {
                if value is NSNull {
                    newDefaults.removeObject(forKey: name)
                    self.debugLog("Removed default event parameter: " + name)
                } else {
                    newDefaults.addEntries(from: [name : value])
                    self.debugLog("Set default event parameter: name, value: \(name), \(value)")
                }
            }
            self.defaultParameters = newDefaults.count > 0 ? newDefaults as? [String : Any] : nil
            if (nil == self.defaultParameters) {
                UserDefaults.standard.removeObject(forKey: self.defaultsKeyDefaultParameters)
            } else {
                UserDefaults.standard.setValue(self.defaultParameters, forKey: self.defaultsKeyDefaultParameters)
            }
        }
    }
    
    /// Logs an  event. The event can have up to 25 parameters, including any default parameters.
    ///
    /// - Parameters:
    ///   - name: The name of the event. Should contain 1 to 40 alphanumeric characters or underscores. The name
    ///       must start with an alphabetic character. Some event names are reserved. See FIREventNames.h for the
    ///       list of reserved event names. The "firebase_", "google_", and "ga_" prefixes are reserved and should not
    ///       be used. Note that event names are case-sensitive and that logging two events whose names differ only
    ///       in case will result in two distinct events.
    ///   - parameters: The dictionary of event parameters. Passing nil indicates that the event has no parameters.
    ///       Parameter names can be up to 40 characters long and must start with an alphabetic character and contain
    ///       only alphanumeric characters and underscores. Only NSString and NSNumber (signed 64-bit integer and
    ///       64-bit floating-point number) parameter types are supported. NSString parameter values can be up to 100
    ///       characters long. The "firebase_", "google_", and "ga_" prefixes are reserved and should not be used for
    ///       parameter names.
    func logEvent(_ name: String, parameters: [String : Any]?) {
        queue.sync {
            debugLog("Logging event: name, params: \(name), " + (parameters?.description ?? "nil"))
            let params = NSMutableDictionary()
            if let defaultParams = defaultParameters {
                params.setDictionary(defaultParams)
            }
            if let eventParams = parameters {
                params.addEntries(from: eventParams)
            }
            validateEvent(name, parameters: parameters)
            sendEvent(name, parameters: (params.count > 0 ? params as? [String : Any] : nil) )
        }
    }
    
    /// Clears all analytics data for this client from the device and resets the device ID.
    func resetAnalyticsData() {
        queue.async (flags: .barrier) {
            self.deviceID = NSUUID().uuidString
            UserDefaults.standard.setValue(self.deviceID, forKey: self.defaultsKeyDeviceID)
            self.userID = nil
            UserDefaults.standard.removeObject(forKey: self.defaultsKeyUserID)
            self.userIsLoggedIn = false
            self.userProperties = nil
            UserDefaults.standard.removeObject(forKey: self.defaultsKeyUserProperties)
            self.defaultParameters = nil
            UserDefaults.standard.removeObject(forKey: self.defaultsKeyDefaultParameters)
        }
    }
    
    // MARK: - Private methods: General
    
    /// Logs message to the console when debugMode is enabled.
    ///
    /// - Parameter message: Message to be logged.
    private func debugLog(_ message: String) {
        if (debugMode) {
            print(message)
        }
    }
    
    // MARK: - Private methods: Networking
    
    /// Handles the HTTP request to upload the event (and other data) to the configured endpoint.
    ///
    /// - Parameters:
    ///   - name: The name of the event.
    ///   - parameters: The dictionary of event parameters.
    private func sendEvent(_ name: String, parameters: [String : Any]?) {
        queue.async(flags: .barrier) {
            guard self.analyticsCollectionEnabled else {
                self.debugLog("Analytics collection is disabled.")
                return
            }
            guard let url = self.makeUrl() else {
                self.debugLog("Invalid endpoint URL")
                return
            }
            self.debugLog("Uploading event: name, params: \(name), " + (parameters?.description ?? "nil"))
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let bodyJson = self.makeBodyJsonForEvent(name, parameters: parameters)
            self.debugLog(bodyJson)
            request.httpBody = bodyJson.data(using: .utf8)
            let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
                if let error = error {
                    self.debugLog("Error during '\(name)' upload: \(error)")
                    return
                }
                if let response = response as? HTTPURLResponse {
                    let statusCode = response.statusCode
                    if statusCode >= 500 {
                        self.debugLog("Server error (\(statusCode)) during '\(name)' upload")
                        // TODO: Implement backoff and retry logic
                    } else {
                        // presumed success
                        self.debugLog("Successful upload for '\(name)'. Status code: \(statusCode)")
                    }
                }
                if (self.debugMode && self.useValidationEndpoint) {
                    if let data = data,
                       let dataString = String(data: data, encoding: .utf8) {
                        self.debugLog("Response for '\(name)' upload:\n\(dataString)")
                    }
                }
            }
            task.resume()
        }
    }
    
    /// Returns appropriate MP URL based on configuration settings.
    ///
    /// - Returns: URL for MP endpoint.
    private func makeUrl() -> URL? {
        let baseUrl = (useValidationEndpoint) ? endPointValidation : endPointProduction
        let measurementIdParam = (useProtocolVersion == .gtag) ? "&measurement_id=" + measurementID : ""
        let appInstanceIdParam = (useProtocolVersion == .firebase) ? "&firebase_app_id=" + firebaseAppID : ""
        return URL(string: baseUrl + "?api_secret=" + apiSecret + measurementIdParam + appInstanceIdParam)
    }
    
    // MARK: - Private methods: JSON formatting
    
    /// Returns JSON string representing the request body.
    ///
    /// - Parameters:
    ///   - eventName: The name of the event.
    ///   - parameters: The dictionary of event parameters.
    /// - Returns: JSON string representing the request body.
    private func makeBodyJsonForEvent(_ eventName: String, parameters: [String : Any]?) -> String {
        var json = "{"
        json.append(makeWebClientIdJson())
        json.append(makeAppInstanceIdJson())
        json.append(makeUserIdJson())
        json.append(makeUserPropertyJson())
        json.append(makeNonPersonalizedAdsJson())
        json.append(makeEventsArrayJson(eventName: eventName, parameters: parameters))
        json.append("}")
        return (debugMode) ? makePrettyJson(json) : json
    }
    
    /// Returns JSON string representing the clientId field (for gtag requests).
    ///
    /// - Returns: JSON string for clientId field.
    private func makeWebClientIdJson() -> String {
        return (useProtocolVersion == .gtag) ? "\"client_id\":\"\(deviceID)\"," : ""
    }
    
    /// Returns JSON string representing the appInstanceId field (for Firebase requests).
    ///
    /// - Returns: JSON string for appInstanceId field.
    private func makeAppInstanceIdJson() -> String {
        return (useProtocolVersion == .firebase) ? "\"app_instance_id\":\"\(deviceID)\"," : ""
    }
    
    /// Returns JSON string representing the userId field. Only included when loggedIn is true.
    ///
    /// - Returns: JSON string for userId field.
    private func makeUserIdJson() -> String {
        return (userIsLoggedIn && nil != userID) ? "\"user_id\":\"\(userID!)\"," : ""
    }
    
    /// Returns JSON string representing the nonPersonalizedAds field. Only included when nonPersonalizedAds is true.
    ///
    /// - Returns: JSON string for nonPersonalizedAds field.
    private func makeNonPersonalizedAdsJson() -> String {
        return (nonPersonalizedAds) ? "\"non_personalized_ads\":true," : ""
    }
    
    /// Returns JSON string representing the userProperties field.
    ///
    /// - Returns: JSON string for userProperties field.
    private func makeUserPropertyJson() -> String {
        var json = ""
        if let userProperties = userProperties {
            json.append("\"user_properties\":{")
            var upJson = ""
            for (upName, upValue) in userProperties {
                if (upJson.count > 0) {
                    upJson.append(",")
                }
                upJson.append("\"\(upName)\":{\"value\":\"\(upValue)\"}")
            }
            json.append(upJson)
            json.append("},")
        }
        return json
    }
    
    /// Returns JSON string representing the events array field.
    ///
    /// - Parameters:
    ///   - eventName: The name of the event.
    ///   - parameters: The dictionary of event parameters.
    /// - Returns:  JSON string for events array field
    private func makeEventsArrayJson(eventName: String, parameters: [String : Any]?) -> String {
        var json = "\"events\":["
        // for each event...
        json.append("{")
        json.append("\"name\":\"\(eventName)\",")
        json.append("\"params\":{")
        if let params = parameters {
            var paramsJson = ""
            for (epName, epValue) in params {
                if(paramsJson.count > 0) {
                    paramsJson.append(",")
                }
                if let epStringValue = epValue as? String {
                    paramsJson.append("\"\(epName)\":\"\(epStringValue)\"")
                } else {
                    paramsJson.append("\"\(epName)\":\(epValue)")
                }
            }
            paramsJson.append("}") // close params
            json.append(paramsJson)
        } else {
            json.append("}")
        }
        json.append("}") // close event
        json.append("]") // close array
        return json
    }
    
    /// Returns "pretty" JSON for debugging purposes.
    /// - Parameter jsonString: String representation of JSON object
    /// - Returns: Pretty version of JSON object.
    private func makePrettyJson(_ jsonString: String) -> String {
        if let json = try? JSONSerialization.jsonObject(with: jsonString.data(using: .utf8)!, options: .mutableContainers),
           let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) {
            return String(decoding: jsonData, as: UTF8.self)
        } else {
            debugLog("Malformed JSON string: " + jsonString)
            return ""
        }
    }
    
    // MARK: - Private methods: Validation
    
    /// Returns compiled regex for event name validation.
    ///
    /// - Returns: Regex.
    private func makeEventNameRegex() -> NSRegularExpression? {
        let regex = String(format: validationRuleEventNamePattern, validationRuleEventNameMaxLength - 1)
        if let pattern = try? NSRegularExpression(pattern: regex) {
            return pattern
        } else {
            let ex = NSException(name: NSExceptionName.invalidArgumentException, reason: "Invalid regex pattern for event name validation", userInfo: nil)
            ex.raise()
        }
        return nil
    }
    
    /// Returns compiled regex for event parameter name validation.
    ///
    /// - Returns: Regex.
    private func makeParameterNameRegex() -> NSRegularExpression? {
        let regex = String(format: validationRuleParameterNamePattern, validationRuleParameterNameMaxLength - 1)
        if let pattern = try? NSRegularExpression(pattern: regex) {
            return pattern
        } else {
            let ex = NSException(name: NSExceptionName.invalidArgumentException, reason: "Invalid regex pattern for parameter name validation", userInfo: nil)
            ex.raise()
        }
        return nil
    }
    
    /// Returns compiled regex for user property name validation.
    ///
    /// - Returns: Regex.
    private func makeUserPropertyNameRegex() -> NSRegularExpression? {
        let regex = String(format: validationRuleUserPropertyNamePattern, validationRuleUserPropertyNameMaxLength - 1)
        if let pattern = try? NSRegularExpression(pattern: regex) {
            return pattern
        } else {
            let ex = NSException(name: NSExceptionName.invalidArgumentException, reason: "Invalid regex pattern for user property name validation", userInfo: nil)
            ex.raise()
        }
        return nil
    }
    
    /// Checks the event name, parameter count, and parameter names and values against the GA4 rules
    /// when debugMode is enabled.
    ///
    /// - Parameters:
    ///   - name: The name of the event
    ///   - parameters: The dictionary of event parameters.
    private func validateEvent(_ name: String, parameters: [String : Any]?) {
        guard debugMode else {return}
        // validate event name
        let isInvalidName = validationRegexEventName?.numberOfMatches(in: name, range: NSMakeRange(0, name.count)) != 1
        if (isInvalidName) {
            let errorMessage = String(format: "Invalid event name '%@'", name)
            handleValidationError(errorMessage)
        }
        // validate parameter count
        if (nil != parameters) {
            let parameterCount = parameters!.count
            let isInvalidCount = parameterCount > validationRuleEventMaxParameters
            if (isInvalidCount) {
                let errorMessage = String(format: "Too many parameters in event '%@': contains %ld, max %ld", name, parameterCount, validationRuleEventMaxParameters)
                handleValidationError(errorMessage)
            }
        }
        // validate parameters
        validateParameters(source: name, parameters: parameters)
    }
    
    /// Checks each event parameter name and value against the GA4 rules when debugMode is enabled.
    ///
    /// - Parameters:
    ///   - source: Source of event parameters (either event name or default event parameters).
    ///   - parameters: The dictionary of event parameters.
    private func validateParameters(source: String, parameters: [String : Any]?) {
        guard debugMode && nil != parameters else {return}
        for (name, value) in parameters! {
            // validate parameter name
            let isInvalidName = validationRegexParameterName?.numberOfMatches(in: name, range: NSMakeRange(0, name.count)) != 1
            if (isInvalidName) {
                let errorMessage = String(format: "Invalid parameter name '%@' in '%@'", name, source)
                handleValidationError(errorMessage)
            }
            // validate parameter value
            if let stringValue = value as? String {
                let isInvalidValue = stringValue.count > validationRuleParameterValueMaxLength
                if (isInvalidValue) {
                    let errorMessage = String(format: "Value too long for parameter '%@' in '%@': %@", name, source, stringValue)
                    handleValidationError(errorMessage)
                }
            }
        }
    }
    
    /// Checks the user property name and value against the GA4 rules when debugMode is enabled.
    ///
    /// Also checks count of user properties against limit.
    ///
    /// - Parameters:
    ///   - value: The value of the user property.
    ///   - name: The name of the user property.
    private func validateUserProperty(_ value: String?, forName name: String) {
        guard debugMode else {return}
        // validate user property name
        let isInvalidName = validationRegexUserPropertyName?.numberOfMatches(in: name, range: NSMakeRange(0, name.count)) != 1
        if (isInvalidName) {
            let errorMessage = String(format: "Invalid user property name '%@'", name)
            handleValidationError(errorMessage)
        }
        // validate user property value
        if (nil != value) {
            let isInvalidValue = value!.count > validationRuleUserPropertyNameMaxLength
            if (isInvalidValue) {
                let errorMessage = String(format: "Value too long for user property '%@': %@", name, value!)
                handleValidationError(errorMessage)
            }
        }
        // validate current count
        if let currentProperties = userProperties {
            if (currentProperties.count > validationRuleUserPropertyMaxCount) {
                let errorMessage = String(format: "Too many user properties: last, set, max: %@, %ld, %ld", name,
                                          currentProperties.count, validationRuleUserPropertyMaxCount)
                handleValidationError(errorMessage)
            }
            
        }
    }
    
    /// Checks the user ID against the GA4 rules when debugMode is enabled.
    ///
    /// - Parameter userID: The value of the user ID.
    private func validateUserID(_ userID: String?) {
        guard debugMode && nil != userID else {return}
        let isInvalidValue = userID!.count > validationRuleUserIDValueMaxLength
        if (isInvalidValue) {
            let errorMessage = String(format: "User ID is too long: %@", userID!)
            handleValidationError(errorMessage)
        }
    }
    
    /// Handles the validation error by logging it, or optionally throwing an NSInvalidArgumentException exception.
    ///
    /// - Parameter errorMessage: The validation error message
    private func handleValidationError(_ errorMessage : String) {
        debugLog(errorMessage)
        if (debugMode && throwOnValidationErrorsInDebug) {
            let ex = NSException(name: NSExceptionName.invalidArgumentException, reason: errorMessage, userInfo: nil)
            ex.raise()
        }
    }
    
    
}
