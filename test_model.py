#!/usr/bin/env python
"""Test script to verify model loading"""
import sys
sys.path.insert(0, '.')

from predict import get_predictor

print('🔍 Testing model initialization...')
model_path = 'model/malabar_mobilenet.pth'

try:
    predictor = get_predictor(model_path, 'cpu')
    print(f'✓ Predictor initialized successfully')
    print(f'  Model class: {predictor.model.__class__.__name__}')
    print(f'  Device: {predictor.device}')
    print(f'✓ Ready for predictions!')
except Exception as e:
    print(f'❌ Error: {e}')
    import traceback
    traceback.print_exc()
