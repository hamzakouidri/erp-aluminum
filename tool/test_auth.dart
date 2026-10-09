import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  const url = 'https://gaifxtuintzftkgqomue.supabase.co';
  const key = 'sb_publishable_p1FfxpQZUzMLM35fxSwP6w_hQAj4rQY';
  const token = 'eyJhbGciOiJFUzI1NiIsImtpZCI6ImNkM2Y4ZmFiLTBhOGEtNDQxMi05Y2YxLTBhODhiYzIxNDg2NyIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJodHRwczovL2dhaWZ4dHVpbnR6ZnRrZ3FvbXVlLnN1cGFiYXNlLmNvL2F1dGgvdjEiLCJzdWIiOiIxMDRiNGVhZi0wMDI5LTRiODctYTZkYS01ZjFhYmEzZmMxZWEiLCJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjoxNzkxNTMyMzgyLCJpYXQiOjE3OTE1Mjg3ODIsImVtYWlsIjoia291aWRyaWhhbXphNDVAZ21haWwuY29tIiwicGhvbmUiOiIiLCJhcHBfbWV0YWRhdGEiOnsicHJvdmlkZXIiOiJlbWFpbCIsInByb3ZpZGVycyI6WyJlbWFpbCIsImdvb2dsZSJdfSwidXNlcl9tZXRhZGF0YSI6eyJhdmF0YXJfdXJsIjoiaHR0cHM6Ly9saDMuZ29vZ2xldXNlcmNvbnRlbnQuY29tL2EvQUNnOG9jSVkwT3phdEZkM3gwTVRjazBXaUVTdjNkdXRvVXBhcTlsV3cxVmpzdEZSVG5Rd0w2WT1zOTYtYyIsImVtYWlsIjoia291aWRyaWhhbXphNDVAZ21haWwuY29tIiwiZW1haWxfdmVyaWZpZWQiOnRydWUsImZ1bGxfbmFtZSI6ImhhbXphIGtvdWlkcmkiLCJpc3MiOiJodHRwczovL2FjY291bnRzLmdvb2dsZS5jb20iLCJuYW1lIjoiaGFtemEga291aWRyaSIsInBob25lX3ZlcmlmaWVkIjpmYWxzZSwicGljdHVyZSI6Imh0dHBzOi8vbGgzLmdvb2dsZXVzZXJjb250ZW50LmNvbS9hL0FDZzhvY0lZME96YXRGZDN4ME1UY2swV2lFU3YzZHV0b1VwYXE5bFd3MVZqc3RGUlRuUXdMNlk9czk2LWMiLCJwcm92aWRlcl9pZCI6IjExNjUwNDM2OTEzMjY1MjIzMDA3MCIsInN1YiI6IjExNjUwNDM2OTEzMjY1MjIzMDA3MCJ9LCJyb2xlIjoiYXV0aGVudGljYXRlZCIsImFhbCI6ImFhbDEiLCJhbXIiOlt7Im1ldGhvZCI6InBhc3N3b3JkIiwidGltZXN0YW1wIjoxNzkxNTI4NzgyfV0sInNlc3Npb25faWQiOiIxZmViMDRlOS01YTVjLTQ3YzUtYTg2Yy0yMTRiNzM4ODRlMTMiLCJpc19hbm9ueW1vdXMiOmZhbHNlfQ.bj65RuRXMcuLXw-pp6DJDVJmHZcQgPWDNYvryYXE9YnhStGIJ_Htp9dd1T7y6Btr1Doke69hRnns7c1st6y68Q';

  final headers = {
    'apikey': key,
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };

  final wsRes = await http.get(Uri.parse('$url/rest/v1/workshops?select=*'), headers: headers);
  print('workshops: ${wsRes.statusCode} ${wsRes.body}');

  final memRes = await http.get(Uri.parse('$url/rest/v1/workshop_members?select=*'), headers: headers);
  print('workshop_members: ${memRes.statusCode} ${memRes.body}');
}
