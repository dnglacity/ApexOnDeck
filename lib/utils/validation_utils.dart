bool isPasswordStrong(String password) {
  return password.contains(RegExp(r'[a-zA-Z]')) &&
      password.contains(RegExp(r'[0-9]'));
}
