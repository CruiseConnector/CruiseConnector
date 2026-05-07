class CruiseDeepLinks {
  CruiseDeepLinks._();

  static const host = 'cruiseconnector.at';
  static const baseUrl = 'https://$host';

  static Uri postUri(String postId) {
    return Uri.https(host, '/', {'post': postId});
  }
}
