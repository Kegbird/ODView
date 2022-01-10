struct Prediction {
    var label: String
    var confidence: Float
    
    func getDescriptionString() -> String
    {
        return String(format: "%@: %.2f", label, confidence*100.0)
    }
}

