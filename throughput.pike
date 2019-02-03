object load_public_key(string fn) {return decode_public_key((Stdio.read_file(fn)/" ")[1]);}
object decode_public_key(string key)
{
	//Decoding technique provided by Henrik Grubbström (grubba) - thanks!
	Stdio.Buffer buf = Stdio.Buffer(MIME.decode_base64(key));
	string tag = buf->read_hstring(4);
	if (tag != "ssh-rsa") error("Incorrect signature on public key (%O)", tag);
	int pub = buf->read_hint(4);
	int modulo = buf->read_hint(4);
	return Crypto.RSA()->set_public_key(modulo, pub);
}

object key1 = load_public_key("server_key.pub");
object key2 = load_public_key("key2.pub");
object voterpriv = Standards.PKCS.RSA.parse_private_key(Standards.PEM.simple_decode(Stdio.read_file("key3")));
object voter = load_public_key("key3.pub");

string seal_ballot(string nonce)
{
	string payload = Standards.JSON.encode((["salt": MIME.encode_base64(random_string(9)),
		"foo": ({"asdf", "qwer", "zxcv"}),
		"bar": ({"qaz", "wsx", "edc"}),
	]));
	string ballot = key1->encrypt(string_to_utf8(payload));
	string sig = voterpriv->pkcs_sign(ballot + nonce, Crypto.SHA256); //Slowest part of this function, right here
	string package = MIME.encode_base64(ballot, 1) + "\n" + MIME.encode_base64(sig, 1) + "\n" + nonce;
	//To ensure consistency, the package should always create the same number of chunks,
	//regardless of the contents of the ballot itself.
	array chunks = package / 245.0;
	return key2->encrypt(chunks[*]) * "";
}

string receive_ballot(object key, string sealed)
{
	array chunks = sealed / 256.0; //Should always be a complete set of chunks
	sscanf(key->decrypt(chunks[*]) * "", "%s\n%s\n%s", string ballot, string sig, string nonce); //Slowest part is hers
	if (!stringp(nonce) || sizeof(nonce) != 12) return 0; //Informal ballot - bad format
	//This is where you'd do a database transaction to validate the nonce and get a voter's public key
	ballot = MIME.decode_base64(ballot);
	sig = MIME.decode_base64(sig);
	if (!voter->pkcs_verify(ballot + nonce, Crypto.SHA256, sig)) return 0; //Informal ballot - sig failed
	return ballot;
}

void count_ballot(object key, string ballot, mapping results)
{
	mapping data = Standards.JSON.decode_utf8(key->decrypt(ballot));
	if (!mappingp(data)) return; //Informal ballot - bad data format
	results[data->foo[0]]++;
}

int main()
{
	object priv1 = Standards.PKCS.RSA.parse_private_key(Standards.PEM.simple_decode(Stdio.read_file("server_key")));
	object priv2 = Standards.PKCS.RSA.parse_private_key(Standards.PEM.simple_decode(Stdio.read_file("key2")));
	string nonce = MIME.encode_base64(random_string(9));
	string sealed_ballot = seal_ballot(nonce);
	string ballot = receive_ballot(priv2, sealed_ballot);
	mapping results = ([]);
	count_ballot(priv1, ballot, results);
	write("Election results: %O\n", results);

	constant seals = 1000;
	float time = gauge {for (int i = 0; i < seals; ++i) seal_ballot(nonce);};
	write("Created %d ballots in %fs for throughput of %f/sec\n", seals, time, seals/time);

	constant unseals = 300;
	time = gauge {for (int i = 0; i < unseals; ++i) receive_ballot(priv2, sealed_ballot);};
	write("Unsealed %d ballots in %fs for throughput of %f/sec\n", unseals, time, unseals/time);

	constant counts = 1000;
	time = gauge {for (int i = 0; i < counts; ++i) count_ballot(priv1, ballot, results);};
	write("Counted %d ballots in %fs for throughput of %f/sec\n", counts, time, counts/time);
}
