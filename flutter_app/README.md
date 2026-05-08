# PhytoAI Flutter App

A complete mobile application for plant disease detection built with Flutter.

## Features

- **Plant Disease Detection**: Take photos or select from gallery to detect plant diseases using AI
- **Prediction History**: View all your previous disease detection results
- **Prevention Tips**: Get prevention and treatment information for specific diseases
- **Drug Classification**: Classify compounds, medicines, and chemical structures
- **User Profile**: Manage your account information
- **Authentication**: Secure login/signup with Supabase

## Setup

1. Install Flutter: https://flutter.dev/docs/get-started/install
2. Clone this repository
3. Navigate to the flutter_app directory
4. Run `flutter pub get` to install dependencies
5. Update the API base URL in `lib/api_service.dart` to point to your backend
6. Run `flutter run` to start the app

## Dependencies

- `http`: For API calls
- `image_picker`: For camera and gallery access
- `supabase_flutter`: For authentication and backend integration
- `provider`: For state management
- `permission_handler`: For handling permissions
- `intl`: For date formatting

## Architecture

- **MVVM Pattern**: Clean separation of concerns
- **Provider**: State management for authentication and app state
- **Service Layer**: API service handles all backend communication
- **Model Classes**: Data models for type safety

## API Integration

The app integrates with a Flask backend API with the following endpoints:

- `POST /api/predict/` - Plant disease detection
- `GET /api/history/history` - User prediction history
- `POST /api/prevention` - Prevention information
- `POST /api/drug/classify` - Drug classification
- `GET /api/profile/profile` - User profile
- `POST /api/history/update-profile` - Update profile

## Permissions

The app requires camera and storage permissions for image capture and selection.

## Building

To build for Android:
```bash
flutter build apk
```

To build for iOS:
```bash
flutter build ios
```

## Screenshots

(Add screenshots here when available)

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is licensed under the MIT License.