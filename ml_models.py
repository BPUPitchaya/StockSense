import yfinance as yf
import pandas as pd
import numpy as np
from typing import Dict, List, Optional, Tuple
from sklearn.ensemble import RandomForestClassifier, RandomForestRegressor
from sklearn.preprocessing import MinMaxScaler
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, classification_report
import joblib
import os

# TensorFlow import - make optional due to Python 3.13 compatibility issues
try:
    import tensorflow as tf
    from tensorflow.keras.models import Sequential
    from tensorflow.keras.layers import LSTM, Dense, Dropout
    TENSORFLOW_AVAILABLE = True
except ImportError:
    TENSORFLOW_AVAILABLE = False
    print("TensorFlow not available. LSTM model disabled. Using Random Forest only.")

class StockDataPreprocessor:
    """Preprocess stock data for ML models"""
    
    def __init__(self):
        self.scaler = MinMaxScaler()
    
    def fetch_historical_data(self, ticker: str, period: str = "5y") -> Optional[pd.DataFrame]:
        """Fetch historical stock data"""
        try:
            stock = yf.Ticker(ticker)
            df = stock.history(period=period)
            if df.empty:
                return None
            return df
        except Exception as e:
            print(f"Error fetching data for {ticker}: {e}")
            return None
    
    def calculate_technical_indicators(self, df: pd.DataFrame) -> pd.DataFrame:
        """Calculate technical indicators for ML features"""
        df = df.copy()
        
        # Moving averages
        df['MA5'] = df['Close'].rolling(window=5).mean()
        df['MA10'] = df['Close'].rolling(window=10).mean()
        df['MA20'] = df['Close'].rolling(window=20).mean()
        df['MA50'] = df['Close'].rolling(window=50).mean()
        
        # RSI
        delta = df['Close'].diff()
        gain = (delta.where(delta > 0, 0)).rolling(window=14).mean()
        loss = (-delta.where(delta < 0, 0)).rolling(window=14).mean()
        rs = gain / loss
        df['RSI'] = 100 - (100 / (1 + rs))
        
        # Price changes
        df['Price_Change'] = df['Close'].pct_change()
        df['Price_Change_5d'] = df['Close'].pct_change(5)
        
        # Volume
        df['Volume_MA'] = df['Volume'].rolling(window=20).mean()
        df['Volume_Ratio'] = df['Volume'] / df['Volume_MA']
        
        # Bollinger Bands
        df['BB_Middle'] = df['Close'].rolling(window=20).mean()
        df['BB_Std'] = df['Close'].rolling(window=20).std()
        df['BB_Upper'] = df['BB_Middle'] + (df['BB_Std'] * 2)
        df['BB_Lower'] = df['BB_Middle'] - (df['BB_Std'] * 2)
        df['BB_Position'] = (df['Close'] - df['BB_Lower']) / (df['BB_Upper'] - df['BB_Lower'])
        
        # MACD
        exp_fast = df['Close'].ewm(span=12, adjust=False).mean()
        exp_slow = df['Close'].ewm(span=26, adjust=False).mean()
        df['MACD'] = exp_fast - exp_slow
        df['MACD_Signal'] = df['MACD'].ewm(span=9, adjust=False).mean()
        df['MACD_Hist'] = df['MACD'] - df['MACD_Signal']
        
        # Drop NaN values
        df = df.dropna()
        
        return df
    
    def create_lstm_sequences(self, data: np.ndarray, sequence_length: int = 60) -> Tuple[np.ndarray, np.ndarray]:
        """Create sequences for LSTM training"""
        X, y = [], []
        for i in range(len(data) - sequence_length):
            X.append(data[i:(i + sequence_length)])
            y.append(data[i + sequence_length])
        return np.array(X), np.array(y)
    
    def create_target_labels(self, df: pd.DataFrame, horizon: int = 5, threshold: float = 0.02) -> np.ndarray:
        """Create target labels for classification (1=up, 0=down/flat)"""
        future_returns = df['Close'].pct_change(horizon).shift(-horizon)
        labels = (future_returns > threshold).astype(int)
        return labels.values[:-horizon]


class LSTMModel:
    """LSTM model for time series prediction (optional, requires TensorFlow)"""
    
    def __init__(self, sequence_length: int = 60, units: int = 50):
        self.sequence_length = sequence_length
        self.units = units
        self.model = None
        self.scaler = MinMaxScaler()
        self.available = TENSORFLOW_AVAILABLE
    
    def build_model(self, input_shape: Tuple[int, int]):
        """Build LSTM model architecture"""
        if not self.available:
            raise RuntimeError("TensorFlow not available. Cannot use LSTM model.")
        
        model = Sequential([
            LSTM(self.units, return_sequences=True, input_shape=input_shape),
            Dropout(0.2),
            LSTM(self.units, return_sequences=False),
            Dropout(0.2),
            Dense(25),
            Dense(1)
        ])
        model.compile(optimizer='adam', loss='mean_squared_error')
        self.model = model
        return model
    
    def train(self, X_train: np.ndarray, y_train: np.ndarray, epochs: int = 50, batch_size: int = 32):
        """Train LSTM model"""
        if not self.available:
            raise RuntimeError("TensorFlow not available. Cannot use LSTM model.")
        
        if self.model is None:
            self.build_model((X_train.shape[1], X_train.shape[2]))
        
        history = self.model.fit(
            X_train, y_train,
            epochs=epochs,
            batch_size=batch_size,
            validation_split=0.2,
            verbose=1
        )
        return history
    
    def predict(self, X: np.ndarray) -> np.ndarray:
        """Make predictions"""
        if not self.available:
            raise RuntimeError("TensorFlow not available. Cannot use LSTM model.")
        
        if self.model is None:
            raise ValueError("Model not trained. Call train() first.")
        return self.model.predict(X)
    
    def save(self, path: str):
        """Save model"""
        if not self.available:
            return
        if self.model is not None:
            self.model.save(path)
            joblib.dump(self.scaler, f"{path}_scaler.pkl")
    
    def load(self, path: str):
        """Load model"""
        if not self.available:
            return False
        try:
            self.model = tf.keras.models.load_model(path)
            self.scaler = joblib.load(f"{path}_scaler.pkl")
            return True
        except:
            return False


class RandomForestModel:
    """Random Forest model for stock prediction classification"""
    
    def __init__(self, n_estimators: int = 100, max_depth: int = 10):
        self.n_estimators = n_estimators
        self.max_depth = max_depth
        self.model = None
    
    def build_model(self):
        """Build Random Forest model"""
        self.model = RandomForestClassifier(
            n_estimators=self.n_estimators,
            max_depth=self.max_depth,
            random_state=42,
            n_jobs=-1
        )
        return self.model
    
    def train(self, X_train: np.ndarray, y_train: np.ndarray):
        """Train Random Forest model"""
        if self.model is None:
            self.build_model()
        
        self.model.fit(X_train, y_train)
        return self.model
    
    def predict(self, X: np.ndarray) -> np.ndarray:
        """Make predictions"""
        if self.model is None:
            raise ValueError("Model not trained. Call train() first.")
        return self.model.predict(X)
    
    def predict_proba(self, X: np.ndarray) -> np.ndarray:
        """Get prediction probabilities"""
        if self.model is None:
            raise ValueError("Model not trained. Call train() first.")
        return self.model.predict_proba(X)
    
    def get_feature_importance(self, feature_names: List[str]) -> Dict[str, float]:
        """Get feature importance"""
        if self.model is None:
            raise ValueError("Model not trained. Call train() first.")
        
        importances = self.model.feature_importances_
        return dict(zip(feature_names, importances))
    
    def save(self, path: str):
        """Save model"""
        if self.model is not None:
            joblib.dump(self.model, path)
    
    def load(self, path: str):
        """Load model"""
        self.model = joblib.load(path)


class EnsemblePredictor:
    """Ensemble predictor combining LSTM and Random Forest"""
    
    def __init__(self):
        self.lstm_model = LSTMModel()
        self.rf_model = RandomForestModel()
        self.preprocessor = StockDataPreprocessor()
        self.lstm_weight = 0.5
        self.rf_weight = 0.5
        self.use_lstm = TENSORFLOW_AVAILABLE
    
    def train_models(self, ticker: str):
        """Train both models on historical data for a stock"""
        df = self.preprocessor.fetch_historical_data(ticker, period="5y")
        if df is None:
            raise ValueError(f"Could not fetch data for {ticker}")
        
        # Calculate technical indicators
        df = self.preprocessor.calculate_technical_indicators(df)
        
        # Train LSTM if available
        if self.use_lstm:
            try:
                # Prepare LSTM data
                price_data = df[['Close', 'MA20', 'MA50', 'RSI', 'MACD']].values
                price_data_scaled = self.lstm_model.scaler.fit_transform(price_data)
                X_lstm, y_lstm = self.preprocessor.create_lstm_sequences(price_data_scaled)
                
                # Train LSTM
                print(f"Training LSTM for {ticker}...")
                self.lstm_model.train(X_lstm, y_lstm, epochs=30, batch_size=32)
                print(f"✓ LSTM trained for {ticker}")
            except Exception as e:
                print(f"✗ LSTM training failed for {ticker}: {e}")
                self.use_lstm = False
        else:
            print(f"LSTM skipped (TensorFlow not available)")
        
        # Train Random Forest
        try:
            feature_cols = ['MA5', 'MA10', 'MA20', 'MA50', 'RSI', 'Price_Change', 
                           'Price_Change_5d', 'Volume_Ratio', 'BB_Position', 'MACD', 'MACD_Hist']
            X_rf = df[feature_cols].values[:-5]  # Remove last 5 rows for target
            y_rf = self.preprocessor.create_target_labels(df)
            
            print(f"Training Random Forest for {ticker}...")
            self.rf_model.train(X_rf, y_rf)
            print(f"✓ Random Forest trained for {ticker}")
        except Exception as e:
            print(f"✗ Random Forest training failed for {ticker}: {e}")
            raise
        
        print(f"Models trained successfully for {ticker}")
    
    def predict(self, ticker: str) -> Dict:
        """Make ensemble prediction for a stock"""
        df = self.preprocessor.fetch_historical_data(ticker, period="1y")
        if df is None:
            return {"error": "Could not fetch data"}
        
        df = self.preprocessor.calculate_technical_indicators(df)
        
        lstm_signal = 0
        if self.use_lstm:
            try:
                # LSTM prediction
                price_data = df[['Close', 'MA20', 'MA50', 'RSI', 'MACD']].values
                price_data_scaled = self.lstm_model.scaler.transform(price_data)
                X_lstm, _ = self.preprocessor.create_lstm_sequences(price_data_scaled)
                
                if len(X_lstm) > 0:
                    lstm_pred = self.lstm_model.predict(X_lstm[-1:])
                    lstm_signal = 1 if lstm_pred[0][0] > price_data[-1][0] else 0
            except:
                lstm_signal = 0
        
        # Random Forest prediction
        try:
            feature_cols = ['MA5', 'MA10', 'MA20', 'MA50', 'RSI', 'Price_Change', 
                           'Price_Change_5d', 'Volume_Ratio', 'BB_Position', 'MACD', 'MACD_Hist']
            X_rf = df[feature_cols].values[-1:].reshape(1, -1)
            rf_pred = self.rf_model.predict(X_rf)[0]
            rf_proba = self.rf_model.predict_proba(X_rf)[0]
        except Exception as e:
            print(f"RF prediction error: {e}")
            return {"error": f"Prediction failed: {e}"}
        
        # Ensemble prediction (use RF only if LSTM unavailable)
        if self.use_lstm:
            ensemble_score = (self.lstm_weight * lstm_signal + self.rf_weight * rf_pred)
        else:
            ensemble_score = rf_pred
        
        confidence = rf_proba[1] * 100
        prediction = "BUY" if ensemble_score > 0.5 else "SELL" if ensemble_score < 0.3 else "HOLD"
        
        result = {
            "ticker": ticker,
            "prediction": prediction,
            "confidence": confidence,
            "rf_signal": rf_pred,
            "rf_probability": rf_proba[1],
            "ensemble_score": ensemble_score,
            "source": "random_forest" if not self.use_lstm else "ensemble"
        }
        
        if self.use_lstm:
            result["lstm_signal"] = lstm_signal
        
        return result
    
    def save_models(self, ticker: str):
        """Save trained models"""
        os.makedirs("models", exist_ok=True)
        self.lstm_model.save(f"models/{ticker}_lstm.h5")
        self.rf_model.save(f"models/{ticker}_rf.pkl")
    
    def load_models(self, ticker: str):
        """Load trained models"""
        lstm_loaded = self.lstm_model.load(f"models/{ticker}_lstm.h5")
        try:
            self.rf_model.load(f"models/{ticker}_rf.pkl")
            return True
        except:
            return False


if __name__ == "__main__":
    # Example usage
    predictor = EnsemblePredictor()
    
    # Train models for a stock
    predictor.train_models("AAPL")
    
    # Save models
    predictor.save_models("AAPL")
    
    # Make prediction
    result = predictor.predict("AAPL")
    print(f"Prediction for AAPL: {result}")
