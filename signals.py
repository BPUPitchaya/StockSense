import yfinance as yf
import pandas as pd
import numpy as np
from typing import List, Dict, Optional
from datetime import datetime
import asyncio
from concurrent.futures import ThreadPoolExecutor
import time
import os
import finnhub

# Categorized watchlist for selective loading (5 stocks to avoid rate limiting while enabling detailed info)
CATEGORIES = {
    "Top Stocks": ["AAPL", "MSFT", "NVDA", "GOOGL", "TSLA"],
}

# Flat watchlist for backward compatibility
WATCHLIST = [stock for stocks in CATEGORIES.values() for stock in stocks]

# Initialize Finnhub client
FINNHUB_API_KEY = os.getenv('FINNHUB_API_KEY', 'd879fr9r01ql0hskrd3gd879fr9r01ql0hskrd40')
finnhub_client = finnhub.Client(api_key=FINNHUB_API_KEY)


def calculate_rsi(df: pd.DataFrame, period: int = 14) -> pd.Series:
    """Calculate RSI manually"""
    delta = df['Close'].diff()
    gain = (delta.where(delta > 0, 0)).rolling(window=period).mean()
    loss = (-delta.where(delta < 0, 0)).rolling(window=period).mean()
    rs = gain / loss
    rsi = 100 - (100 / (1 + rs))
    return rsi


def calculate_macd(df: pd.DataFrame, fast: int = 12, slow: int = 26, signal: int = 9) -> Dict:
    """Calculate MACD indicator"""
    exp_fast = df['Close'].ewm(span=fast, adjust=False).mean()
    exp_slow = df['Close'].ewm(span=slow, adjust=False).mean()
    macd_line = exp_fast - exp_slow
    signal_line = macd_line.ewm(span=signal, adjust=False).mean()
    histogram = macd_line - signal_line
    
    return {
        'macd_line': macd_line.iloc[-1] if len(macd_line) > 0 else None,
        'signal_line': signal_line.iloc[-1] if len(signal_line) > 0 else None,
        'histogram': histogram.iloc[-1] if len(histogram) > 0 else None,
        'macd_above_signal': macd_line.iloc[-1] > signal_line.iloc[-1] if len(macd_line) > 0 and len(signal_line) > 0 else False,
    }


def calculate_bollinger_bands(df: pd.DataFrame, period: int = 20, std_dev: int = 2) -> Dict:
    """Calculate Bollinger Bands"""
    sma = df['Close'].rolling(window=period).mean()
    std = df['Close'].rolling(window=period).std()
    upper_band = sma + (std * std_dev)
    lower_band = sma - (std * std_dev)
    
    current_price = df['Close'].iloc[-1]
    upper = upper_band.iloc[-1] if len(upper_band) > 0 else None
    lower = lower_band.iloc[-1] if len(lower_band) > 0 else None
    
    # Determine position relative to bands
    if upper and lower:
        band_width = upper - lower
        position = (current_price - lower) / band_width if band_width > 0 else 0.5
    else:
        position = 0.5
    
    return {
        'upper_band': upper,
        'middle_band': sma.iloc[-1] if len(sma) > 0 else None,
        'lower_band': lower,
        'position': position,  # 0 = at lower band, 1 = at upper band
        'near_upper': position > 0.8 if upper and lower else False,
        'near_lower': position < 0.2 if upper and lower else False,
    }


def calculate_volume_trend(df: pd.DataFrame, period: int = 20) -> Dict:
    """Calculate volume analysis"""
    avg_volume = df['Volume'].rolling(window=period).mean()
    current_volume = df['Volume'].iloc[-1]
    relative_volume = current_volume / avg_volume.iloc[-1] if len(avg_volume) > 0 and avg_volume.iloc[-1] > 0 else 1
    
    # Check if volume is increasing or decreasing
    volume_trend = df['Volume'].tail(5).mean() / df['Volume'].tail(10).mean() if len(df) >= 10 else 1
    
    return {
        'avg_volume': avg_volume.iloc[-1] if len(avg_volume) > 0 else None,
        'current_volume': current_volume,
        'relative_volume': relative_volume,
        'high_volume': relative_volume > 1.5,
        'low_volume': relative_volume < 0.5,
        'volume_increasing': volume_trend > 1.1,
    }


def calculate_adx(df: pd.DataFrame, period: int = 14) -> Dict:
    """Calculate ADX (Average Directional Index) for trend strength"""
    high = df['High']
    low = df['Low']
    close = df['Close']
    
    # Calculate True Range
    tr1 = high - low
    tr2 = (high - close.shift()).abs()
    tr3 = (low - close.shift()).abs()
    tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
    atr = tr.rolling(window=period).mean()
    
    # Calculate directional movements
    plus_dm = high.diff()
    minus_dm = -low.diff()
    plus_dm[plus_dm < 0] = 0
    minus_dm[minus_dm < 0] = 0
    plus_dm[plus_dm < minus_dm] = 0
    minus_dm[minus_dm < plus_dm] = 0
    
    # Calculate smoothed directional movements
    plus_di = 100 * (plus_dm.rolling(window=period).mean() / atr)
    minus_di = 100 * (minus_dm.rolling(window=period).mean() / atr)
    
    # Calculate ADX
    dx = 100 * (plus_di - minus_di).abs() / (plus_di + minus_di)
    adx = dx.rolling(window=period).mean()
    
    return {
        'adx': adx.iloc[-1] if len(adx) > 0 else None,
        'plus_di': plus_di.iloc[-1] if len(plus_di) > 0 else None,
        'minus_di': minus_di.iloc[-1] if len(minus_di) > 0 else None,
        'trend_strength': 'Strong' if adx.iloc[-1] > 40 else ( 'Moderate' if adx.iloc[-1] > 20 else 'Weak') if len(adx) > 0 else 'Weak',
        'bullish_trend': plus_di.iloc[-1] > minus_di.iloc[-1] if len(plus_di) > 0 and len(minus_di) > 0 else False,
    }


def analyze_timeframe(df: pd.DataFrame, timeframe: str) -> Dict:
    """Analyze a specific timeframe (daily, weekly, monthly)"""
    if df is None or len(df) < 50:
        return {'timeframe': timeframe, 'signal': 'insufficient_data'}
    
    # Calculate indicators for this timeframe
    ma_short = df['Close'].rolling(window=20).mean().iloc[-1]
    ma_long = df['Close'].rolling(window=50).mean().iloc[-1]
    current_price = df['Close'].iloc[-1]
    rsi = calculate_rsi(df, 14).iloc[-1]
    
    # Determine trend direction
    if current_price > ma_short > ma_long:
        trend = 'bullish'
    elif current_price < ma_short < ma_long:
        trend = 'bearish'
    else:
        trend = 'neutral'
    
    # Determine signal
    if trend == 'bullish' and rsi < 40:
        signal = 'bullish'
    elif trend == 'bearish' and rsi > 60:
        signal = 'bearish'
    elif trend == 'bullish':
        signal = 'bullish'
    elif trend == 'bearish':
        signal = 'bearish'
    else:
        signal = 'neutral'
    
    return {
        'timeframe': timeframe,
        'trend': trend,
        'signal': signal,
        'current_price': current_price,
        'ma_short': ma_short,
        'ma_long': ma_long,
        'rsi': rsi,
    }


def get_stock_data(ticker: str, period: str = "1y") -> Optional[pd.DataFrame]:
    """Fetch historical stock data from yfinance"""
    try:
        stock = yf.Ticker(ticker)
        df = stock.history(period=period)
        if df.empty:
            return None
        return df
    except Exception as e:
        print(f"Error fetching data for {ticker}: {e}")
        return None


def calculate_indicators(df: pd.DataFrame) -> Dict:
    """Calculate all technical indicators"""
    if df is None or len(df) < 200:
        return None
    
    # Calculate moving averages
    df['MA50'] = df['Close'].rolling(window=50).mean()
    df['MA200'] = df['Close'].rolling(window=200).mean()
    
    # Calculate RSI
    df['RSI'] = calculate_rsi(df, period=14)
    
    # Calculate new indicators
    macd = calculate_macd(df)
    bollinger = calculate_bollinger_bands(df)
    volume = calculate_volume_trend(df)
    adx = calculate_adx(df)
    
    # Get latest values
    latest = df.iloc[-1]
    
    return {
        'ticker': None,  # Will be set by caller
        'current_price': float(latest['Close']),
        'ma50': float(latest['MA50']) if pd.notna(latest['MA50']) else None,
        'ma200': float(latest['MA200']) if pd.notna(latest['MA200']) else None,
        'rsi': float(latest['RSI']) if pd.notna(latest['RSI']) else None,
        'date': df.index[-1].strftime('%Y-%m-%d'),
        'macd': macd,
        'bollinger': bollinger,
        'volume': volume,
        'adx': adx,
    }


def generate_signal(indicators: Dict) -> str:
    """
    Generate trading signal based on multiple indicators for better accuracy:
    - BUY: Strong upward momentum, oversold conditions, or multiple bullish indicators
    - SELL: Strong downward momentum, overbought conditions, or multiple bearish indicators
    - HOLD: Mixed or unclear signals
    """
    if indicators is None:
        return "NO_DATA"
    
    current_price = indicators['current_price']
    ma50 = indicators['ma50']
    ma200 = indicators['ma200']
    rsi = indicators['rsi']
    macd = indicators.get('macd', {})
    bollinger = indicators.get('bollinger', {})
    volume = indicators.get('volume', {})
    
    if ma50 is None or rsi is None:
        return "INSUFFICIENT_DATA"
    
    # Count bullish and bearish signals
    bullish_signals = 0
    bearish_signals = 0
    
    # Price vs MA signals (momentum-based)
    if current_price > ma50:
        bullish_signals += 1  # Above MA50 shows strength
    elif current_price < ma50:
        bearish_signals += 1  # Below MA50 shows weakness
    
    if ma200 and current_price > ma200:
        bullish_signals += 1  # Above MA200 shows long-term strength
    elif ma200 and current_price < ma200:
        bearish_signals += 1  # Below MA200 shows long-term weakness
    
    # RSI signals
    if rsi < 30:
        bullish_signals += 2  # Oversold is strong bullish signal
    elif rsi < 45:
        bullish_signals += 1  # Slightly oversold
    elif rsi > 70:
        bearish_signals += 2  # Overbought is strong bearish signal
    elif rsi > 55:
        bearish_signals += 1  # Slightly overbought
    
    # MACD signals
    if macd:
        macd_value = macd.get('macd', 0)
        signal_value = macd.get('signal', 0)
        if macd_value > signal_value:
            bullish_signals += 1  # MACD above signal = bullish
        elif macd_value < signal_value:
            bearish_signals += 1  # MACD below signal = bearish
        
        # MACD histogram
        histogram = macd_value - signal_value
        if histogram > 0 and macd_value > 0:
            bullish_signals += 1  # Positive and rising MACD
        elif histogram < 0 and macd_value < 0:
            bearish_signals += 1  # Negative and falling MACD
    
    # Bollinger Bands signals
    if bollinger:
        upper = bollinger.get('upper')
        lower = bollinger.get('lower')
        if lower and current_price < lower:
            bullish_signals += 2  # Below lower band is strong buy
        elif upper and current_price > upper:
            bearish_signals += 2  # Above upper band is strong sell
    
    # Volume trend signals
    if volume:
        trend = volume.get('trend')
        if trend == 'increasing':
            if current_price > ma50:
                bullish_signals += 1  # Volume + price up = strong buy
            else:
                bearish_signals += 1  # Volume + price down = strong sell
    
    # Generate final signal based on weighted signals
    if bullish_signals >= 2:
        return "BUY"
    elif bearish_signals >= 2:
        return "SELL"
    elif bullish_signals > bearish_signals:
        return "HOLD"
    elif bearish_signals > bullish_signals:
        return "HOLD"
    else:
        return "HOLD"


def analyze_stock(ticker: str) -> Optional[Dict]:
    """Analyze a single stock and return indicators with signal"""
    df = get_stock_data(ticker)
    if df is None:
        return None
    
    indicators = calculate_indicators(df)
    if indicators is None:
        return None
    
    indicators['ticker'] = ticker
    indicators['signal'] = generate_signal(indicators)
    
    return indicators


def get_all_signals() -> List[Dict]:
    """Get signals for all stocks in watchlist"""
    signals = []
    
    for ticker in WATCHLIST:
        print(f"Analyzing {ticker}...")
        result = analyze_stock(ticker)
        if result:
            signals.append(result)
        time.sleep(2.0)  # Increase delay to 2 seconds to prevent rate limiting
    
    return signals


def get_stock_history(ticker: str, period: str = "3mo") -> Optional[List[Dict]]:
    """Get historical price data for a stock"""
    print(f"Fetching history for {ticker} with period {period}")
    df = get_stock_data(ticker, period)
    if df is None:
        print(f"No data returned for {ticker}")
        return None
    
    print(f"Data shape: {df.shape}")
    history = []
    for date, row in df.iterrows():
        history.append({
            'date': date.strftime('%Y-%m-%d'),
            'open': float(row['Open']),
            'high': float(row['High']),
            'low': float(row['Low']),
            'close': float(row['Close']),
            'volume': int(row['Volume'])
        })
    
    print(f"Returning {len(history)} data points")
    return history


def get_stock_info_finnhub(ticker: str) -> Optional[Dict]:
    """Get stock information from Finnhub API (more reliable for current price and company info)"""
    try:
        # Get quote (current price)
        quote = finnhub_client.quote(ticker)
        if not quote or quote.get('c') is None:
            return None
        
        # Get company profile
        profile = finnhub_client.company_profile2(symbol=ticker)
        
        # Check if Finnhub has comprehensive data
        has_comprehensive_data = False
        if profile:
            # Check if Finnhub provides key financial metrics
            if (profile.get('pe') is not None or 
                profile.get('dividendYield') is not None or 
                profile.get('beta') is not None or 
                profile.get('eps') is not None):
                has_comprehensive_data = True
        
        # Only call yfinance if Finnhub doesn't have comprehensive data
        yfinance_info = None
        if not has_comprehensive_data:
            try:
                yfinance_info = get_stock_info(ticker)
            except Exception as e:
                print(f"yfinance fallback failed for {ticker}: {e}")
        
        return {
            'ticker': ticker,
            'current_price': quote.get('c'),  # Current price
            'change': quote.get('d'),  # Change
            'percent_change': quote.get('dp'),  # Percent change
            'high': quote.get('h'),  # High of the day
            'low': quote.get('l'),  # Low of the day
            'open': quote.get('o'),  # Open price
            'previous_close': quote.get('pc'),  # Previous close
            'market_cap': profile.get('marketCapitalization') if profile else None,
            'pe_ratio': yfinance_info.get('pe_ratio') if yfinance_info else profile.get('pe') if profile else None,
            'dividend_yield': yfinance_info.get('dividend_yield') if yfinance_info else profile.get('dividendYield') if profile else None,
            'dividend_rate': yfinance_info.get('dividend_rate') if yfinance_info else None,
            'beta': yfinance_info.get('beta') if yfinance_info else profile.get('beta') if profile else None,
            'eps': yfinance_info.get('eps') if yfinance_info else profile.get('eps') if profile else None,
            'avg_volume': yfinance_info.get('avg_volume') if yfinance_info else None,
            '52_week_high': yfinance_info.get('52_week_high') if yfinance_info else profile.get('52WeekHigh') if profile else None,
            '52_week_low': yfinance_info.get('52_week_low') if yfinance_info else profile.get('52WeekLow') if profile else None,
            'profit_margin': yfinance_info.get('profit_margin') if yfinance_info else None,
            'industry': profile.get('industry') if profile else (yfinance_info.get('industry') if yfinance_info else None),
            'sector': profile.get('sector') if profile else (yfinance_info.get('sector') if yfinance_info else None),
            'description': profile.get('description') if profile else (yfinance_info.get('longBusinessSummary') if yfinance_info else None),
            'country': profile.get('country') if profile else None,
            'exchange': profile.get('exchange') if profile else None,
            'currency': profile.get('currency') if profile else None,
            'source': 'finnhub'
        }
    except Exception as e:
        print(f"Error fetching Finnhub info for {ticker}: {e}")
        return None


def get_stock_info(ticker: str) -> Optional[Dict]:
    """Get detailed stock information"""
    try:
        time.sleep(2.0)  # Increase delay to 2 seconds to prevent rate limiting
        stock = yf.Ticker(ticker)
        info = stock.info
        
        if not info:
            return None
        
        return {
            'ticker': ticker,
            'current_price': info.get('currentPrice') or info.get('regularMarketPrice'),
            'market_cap': info.get('marketCap'),
            'pe_ratio': info.get('trailingPE') or info.get('forwardPE'),
            'dividend_yield': info.get('dividendYield'),
            'dividend_rate': info.get('dividendRate'),
            'beta': info.get('beta'),
            'eps': info.get('trailingEps') or info.get('forwardEps'),
            'avg_volume': info.get('averageVolume') or info.get('averageVolume10days'),
            '52_week_high': info.get('fiftyTwoWeekHigh'),
            '52_week_low': info.get('fiftyTwoWeekLow'),
            'profit_margin': info.get('profitMargins'),
            'revenue': info.get('totalRevenue'),
        }
    except Exception as e:
        print(f"Error fetching info for {ticker}: {e}")
        return None


def predict_stock(ticker: str) -> Optional[Dict]:
    """Predict stock movement for the next month based on technical indicators"""
    try:
        result = analyze_stock(ticker)
        if not result:
            return None
        
        current_price = result['current_price']
        ma50 = result['ma50']
        ma200 = result['ma200']
        rsi = result['rsi']
        macd = result.get('macd', {})
        bollinger = result.get('bollinger', {})
        volume = result.get('volume', {})
        adx = result.get('adx', {})
        
        # Analyze multiple timeframes
        daily_df = get_stock_data(ticker, "1y")
        weekly_df = get_stock_data(ticker, "2y")
        monthly_df = get_stock_data(ticker, "5y")
        
        # Resample for weekly and monthly
        if weekly_df is not None:
            weekly_df = weekly_df.resample('W').agg({
                'Open': 'first',
                'High': 'max',
                'Low': 'min',
                'Close': 'last',
                'Volume': 'sum'
            }).dropna()
        
        if monthly_df is not None:
            monthly_df = monthly_df.resample('ME').agg({
                'Open': 'first',
                'High': 'max',
                'Low': 'min',
                'Close': 'last',
                'Volume': 'sum'
            }).dropna()
        
        daily_analysis = analyze_timeframe(daily_df, 'daily')
        weekly_analysis = analyze_timeframe(weekly_df, 'weekly')
        monthly_analysis = analyze_timeframe(monthly_df, 'monthly')
        
        # Trend strength filter: Only predict if ADX > 20 (strong enough trend)
        adx_value = adx.get('adx')
        if adx_value is None or adx_value < 20:
            return {
                'ticker': ticker,
                'prediction': 'Hold',
                'confidence': 40,
                'potential_change': 0,
                'score': 0,
                'factors': ['Weak trend (ADX < 20) - insufficient trend strength for prediction'],
                'current_price': current_price,
                'rsi': rsi,
                'ma50': ma50,
                'ma200': ma200,
                'adx': adx_value,
                'trend_strength': adx.get('trend_strength', 'Weak'),
                'timeframe_analysis': {
                    'daily': daily_analysis,
                    'weekly': weekly_analysis,
                    'monthly': monthly_analysis,
                },
            }
        
        # Calculate weighted prediction score
        score = 0
        factors = []
        
        # RSI analysis (weight: 1.5)
        if rsi < 30:
            score += 1.5
            factors.append('RSI oversold (<30)')
        elif rsi < 40:
            score += 0.75
            factors.append('RSI approaching oversold')
        elif rsi > 70:
            score -= 1.5
            factors.append('RSI overbought (>70)')
        elif rsi > 60:
            score -= 0.75
            factors.append('RSI approaching overbought')
        
        # MACD analysis (weight: 2.0)
        if macd.get('macd_above_signal'):
            if macd.get('histogram', 0) > 0:
                score += 2.0
                factors.append('MACD bullish crossover with positive histogram')
            else:
                score += 1.0
                factors.append('MACD above signal line')
        else:
            if macd.get('histogram', 0) < 0:
                score -= 2.0
                factors.append('MACD bearish crossover with negative histogram')
            else:
                score -= 1.0
                factors.append('MACD below signal line')
        
        # Bollinger Bands analysis (weight: 1.5)
        if bollinger.get('near_lower'):
            score += 1.5
            factors.append('Price near lower Bollinger Band (oversold)')
        elif bollinger.get('near_upper'):
            score -= 1.5
            factors.append('Price near upper Bollinger Band (overbought)')
        elif bollinger.get('position', 0.5) < 0.3:
            score += 0.75
            factors.append('Price in lower Bollinger Band region')
        elif bollinger.get('position', 0.5) > 0.7:
            score -= 0.75
            factors.append('Price in upper Bollinger Band region')
        
        # Volume analysis (weight: 1.0)
        if volume.get('high_volume') and score > 0:
            score += 1.0
            factors.append('High volume confirming bullish move')
        elif volume.get('high_volume') and score < 0:
            score -= 1.0
            factors.append('High volume confirming bearish move')
        elif volume.get('low_volume'):
            factors.append('Low volume - weak confirmation')
        
        # Moving average analysis (weight: 1.5)
        if ma50 and ma200:
            if current_price > ma50 > ma200:
                score += 1.5
                factors.append('Price above 50-day MA, 50-day above 200-day MA (bullish)')
            elif current_price > ma50:
                score += 0.75
                factors.append('Price above 50-day MA')
            elif current_price < ma50 < ma200:
                score -= 1.5
                factors.append('Price below 50-day MA, 50-day below 200-day MA (bearish)')
            elif current_price < ma50:
                score -= 0.75
                factors.append('Price below 50-day MA')
            
            if ma50 > ma200:
                score += 0.75
                factors.append('50-day MA above 200-day MA (golden cross)')
            else:
                score -= 0.75
                factors.append('50-day MA below 200-day MA (death cross)')
        
        # ADX trend direction (weight: 1.5)
        if adx.get('bullish_trend'):
            score += 0.75
            factors.append('Bullish trend direction (+DI > -DI)')
        else:
            score -= 0.75
            factors.append('Bearish trend direction (+DI < -DI)')
        
        # Multiple timeframe confirmation (weight: 2.0)
        timeframe_signals = []
        if daily_analysis.get('signal') != 'insufficient_data':
            timeframe_signals.append(daily_analysis['signal'])
        if weekly_analysis.get('signal') != 'insufficient_data':
            timeframe_signals.append(weekly_analysis['signal'])
        if monthly_analysis.get('signal') != 'insufficient_data':
            timeframe_signals.append(monthly_analysis['signal'])
        
        bullish_count = timeframe_signals.count('bullish')
        bearish_count = timeframe_signals.count('bearish')
        
        if bullish_count >= 2:
            score += 2.0
            factors.append(f'Timeframe confirmation: {bullish_count}/3 bullish')
        elif bearish_count >= 2:
            score -= 2.0
            factors.append(f'Timeframe confirmation: {bearish_count}/3 bearish')
        elif bullish_count == 1 and bearish_count == 0:
            score += 1.0
            factors.append('Timeframe confirmation: 1 bullish')
        elif bearish_count == 1 and bullish_count == 0:
            score -= 1.0
            factors.append('Timeframe confirmation: 1 bearish')
        else:
            factors.append('Timeframe confirmation: Mixed signals')
        
        # Determine prediction based on weighted score
        if score >= 5:
            prediction = 'Strong Buy'
            confidence = min(95, 60 + score * 5)
        elif score >= 3:
            prediction = 'Buy'
            confidence = min(85, 50 + score * 8)
        elif score <= -5:
            prediction = 'Strong Sell'
            confidence = min(95, 60 + abs(score) * 5)
        elif score <= -3:
            prediction = 'Sell'
            confidence = min(85, 50 + abs(score) * 8)
        else:
            prediction = 'Hold'
            confidence = 50
        
        # Estimate potential change
        potential_change = 0
        if prediction in ['Strong Buy', 'Buy']:
            potential_change = score * 1.2  # Estimate 1.2% per score point
        elif prediction in ['Strong Sell', 'Sell']:
            potential_change = score * 1.2  # Negative for sell
        
        return {
            'ticker': ticker,
            'prediction': prediction,
            'confidence': confidence,
            'potential_change': potential_change,
            'score': score,
            'factors': factors,
            'current_price': current_price,
            'rsi': rsi,
            'ma50': ma50,
            'ma200': ma200,
            'adx': adx_value,
            'trend_strength': adx.get('trend_strength', 'Unknown'),
            'timeframe_analysis': {
                'daily': daily_analysis,
                'weekly': weekly_analysis,
                'monthly': monthly_analysis,
            },
        }
    except Exception as e:
        print(f"Error predicting {ticker}: {e}")
        return None


def get_all_signals(category: Optional[str] = None) -> List[Dict]:
    """Get trading signals for watchlist stocks using parallel processing"""
    # Use category-specific watchlist if provided
    target_watchlist = CATEGORIES.get(category, WATCHLIST) if category else WATCHLIST
    
    signals_data = []
    
    print(f"Fetching signals for {len(target_watchlist)} stocks in {category or 'all'} category...")
    
    # Use ThreadPoolExecutor for parallel processing
    with ThreadPoolExecutor(max_workers=10) as executor:
        future_to_ticker = {
            executor.submit(analyze_stock, ticker): ticker 
            for ticker in target_watchlist
        }
        
        for future in future_to_ticker:
            ticker = future_to_ticker[future]
            try:
                result = future.result()
                if result:
                    signals_data.append(result)
                    print(f"✓ {ticker}")
            except Exception as e:
                print(f"✗ {ticker} failed: {e}")
    
    print(f"Completed {len(signals_data)} signals")
    return signals_data


def get_all_predictions(category: Optional[str] = None, limit: int = 5, watchlist: Optional[List[str]] = None) -> List[Dict]:
    """Get predictions for watchlist stocks using parallel processing"""
    # Use provided watchlist or combine personal with default
    if watchlist is not None:
        target_watchlist = watchlist
        print(f"Using provided watchlist with {len(target_watchlist)} stocks")
    else:
        try:
            import database
            personal_watchlist = database.get_personal_watchlist()
            default_watchlist = CATEGORIES.get(category, WATCHLIST) if category else WATCHLIST
            
            # Combine both watchlists and remove duplicates
            combined_watchlist = list(set(personal_watchlist + default_watchlist))
            target_watchlist = combined_watchlist if combined_watchlist else default_watchlist
            
            print(f"Using combined watchlist with {len(target_watchlist)} stocks (personal: {len(personal_watchlist)}, default: {len(default_watchlist)})")
        except Exception as e:
            print(f"Error fetching personal watchlist, using default: {e}")
            target_watchlist = CATEGORIES.get(category, WATCHLIST) if category else WATCHLIST
    
    predictions = []
    
    print(f"Predicting {len(target_watchlist)} stocks in {category or 'all'} category...")
    
    # Use ThreadPoolExecutor for parallel processing
    with ThreadPoolExecutor(max_workers=10) as executor:
        future_to_ticker = {
            executor.submit(predict_stock, ticker): ticker 
            for ticker in target_watchlist
        }
        
        for future in future_to_ticker:
            ticker = future_to_ticker[future]
            try:
                result = future.result()
                if result:
                    predictions.append(result)
                    print(f"✓ {ticker}")
            except Exception as e:
                print(f"✗ {ticker} failed: {e}")
    
    # Sort by score (highest to lowest)
    predictions.sort(key=lambda x: x['score'], reverse=True)
    
    # Separate gainers and losers by score (top 3 gains, bottom 3 losses)
    gainers = predictions[:3]  # Top 3 highest scores
    losers = predictions[-3:] if len(predictions) >= 3 else predictions  # Bottom 3 lowest scores
    
    # Return combined result
    result = {
        'gainers': gainers,
        'losers': losers,
        'category': category or 'all',
        'total_analyzed': len(predictions)
    }
    
    print(f"Completed {len(predictions)} predictions. Top {len(gainers)} gainers, {len(losers)} losers")
    return result


if __name__ == "__main__":
    signals = get_all_signals()
    print("\n=== Trading Signals ===")
    for signal in signals:
        print(f"\nTicker: {signal['ticker']}")
        print(f"Current Price: ${signal['current_price']:.2f}")
        print(f"50-day MA: ${signal['ma50']:.2f}")
        print(f"200-day MA: ${signal['ma200']:.2f}")
        print(f"RSI: {signal['rsi']:.2f}")
        print(f"Signal: {signal['signal']}")
