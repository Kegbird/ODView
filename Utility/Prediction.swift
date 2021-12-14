struct Prediction {
    let classification: String
    let confidencePercentage: Float
    
    func getDescriptionString() -> String
    {
        return String(format: "%@: %.2f", classification, confidencePercentage*100.0)
    }
}

