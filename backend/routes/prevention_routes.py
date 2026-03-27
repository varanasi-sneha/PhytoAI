from flask import Blueprint, request, jsonify
from backend.services.prevention_service import get_prevention_data

prevention_bp = Blueprint('prevention', __name__)

@prevention_bp.route('/api/prevention', methods=['POST'])
def get_prevention():
    try:
        data = request.get_json()
        disease_name = data.get('disease_name')

        if not disease_name:
            return jsonify({'error': 'disease_name is required'}), 400

        result = get_prevention_data(disease_name)

        if result:
            return jsonify({'success': True, 'data': result}), 200
        else:
            return jsonify({'error': f'No data found for: {disease_name}'}), 404

    except Exception as e:
        return jsonify({'error': str(e)}), 500