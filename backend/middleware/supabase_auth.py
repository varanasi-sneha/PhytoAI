from functools import wraps
from flask import request, jsonify
from backend.utils.supabase_client import supabase

def supabase_auth_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        token = None
        
        # Ensure token is passed in the headers
        if 'Authorization' in request.headers:
            auth_header = request.headers['Authorization']
            if auth_header.startswith("Bearer "):
                token = auth_header.split(" ")[1]
                
        if not token:
            return jsonify({'error': 'Token is missing! Please login.'}), 401
            
        try:
            # Validate token with Supabase
            user_response = supabase.auth.get_user(token)
            if not user_response or not user_response.user:
                return jsonify({'error': 'Token is invalid or expired! Please login again.'}), 401
                
            current_user = user_response.user.id
        except Exception as e:
            return jsonify({'error': str(e)}), 401
            
        return f(current_user, *args, **kwargs)
        
    return decorated
