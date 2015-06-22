inherit "thirdsquare.pike";

constant server_ip = "127.0.0.1";
mapping(int:function) services=([0|HOGAN_UDP:decode_packet]);

//IDs that we're awaiting responses for (mapped to [retry_count, data])
mapping(int:array(int|string)) awaiting=([]);
constant retry_delay = ({2, 3, 5, 10, 15, 25, 60, 120, 120, 120, 120}); //Retry for a maximum of ten minutes before giving up. If a bus stops for ten mins in a dead spot, we have a problem.

//For debugging, enable a console log of incoming packets
#define VERBOSE

object timer;

void handle_packet(string body, string ip, int port)
{
	#ifdef VERBOSE
	write("Response body: %s\n",body);
	#endif
	if (body == "OK") {write("OK response received in %f seconds.\n", timer->peek()); return;}
}

void console()
{
	G->G->consolethread = this_thread();
	write(">> Entering interactive mode\n");
	while (string cmd=Stdio.stdin.gets()) switch (lower_case(cmd))
	{
		case "helo": timer = System.Timer(); send_packet("HELO", server_ip, 5000); break;
		case "quit": exit(0);
		default: write("What?\n");
	}
}

void create()
{
	public_keys[server_ip] = load_public_key("server_key.pub");
	//The public key, being non-sensitive, could actually be embedded into the source, eg:
	//server_key = decode_public_key("AAAAB3NzaC1yc2EAAAADAQABAAABAQDLEtSgsfwoLf6L1nD2gLhKYPpq+PuwLtFlOdAccATOU1IcOiw149HpDh/XhUaNz7yOm6gUHk51tiL8faJt7SrTltp0ayFJbl0+6UaveCXeDfhkIL15H+Rb/1TU2BuQKDbaTiBfzW2QduZDvyyyZHtLp+fD54b1YbyRH5beiS4wEG/7j8lNM+m6tQ0N4HjRUsAMYwy6fzpOCE9HxGHtTeDglS6wvYh1qJ6c4UqYxs8E/LUnQFGZFnEkNqCVxBl3UF20BgEYS/eb+nswBOeQL0z7o5b1+1QLV150kh9FbA7oM5iokLs8OL7e1mSqqUQ9GaYHEhuKAtTehUuc5Onwzmkx");
	if (!file_stat("client_key"))
	{
		Process.create_process(({"ssh-keygen","-q","-N","","-f","client_key"}))->wait();
		//For proof-of-concept, assume that the server reads its client keys from the same
		//directory that we're running from. In live usage, this key transmission would
		//have to be done in some secure way and would need to register an IP address too.
		//It'd also need to SIGHUP the server, else it won't know to check.
		[string type, string key, string sig] = Stdio.read_file("client_key.pub")/" ";
		Stdio.append_file("client_keys", type + " " + key + " 127.0.0.1\n"); //The client's IP address
		sscanf(Process.run(({"netstat","-nulp6"}))->stdout, "%*s :::5000%*[ ]:::* %d/%[^ \n]",int pid,string name);
		if (name == "pike") kill(pid,1);
	}
	private_key = load_private_key("client_key");
	if (!G->G->consolethread) call_out(Thread.Thread,0,console);
}
