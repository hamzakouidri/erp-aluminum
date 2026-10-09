import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  const url = 'https://gaifxtuintzftkgqomue.supabase.co';
  const key = 'sb_publishable_p1FfxpQZUzMLM35fxSwP6w_hQAj4rQY';

  final mRes = await http.get(Uri.parse('$url/rest/v1/catalog_manifest?select=*'), headers: {'apikey': key});
  print('catalog_manifest: ${mRes.statusCode} ${mRes.body}');

  final cRes = await http.get(Uri.parse('$url/rest/v1/catalog_chunks?select=table_name,chunk_index,row_count,version_id&limit=20'), headers: {'apikey': key});
  print('catalog_chunks: ${cRes.statusCode} ${cRes.body}');
}
