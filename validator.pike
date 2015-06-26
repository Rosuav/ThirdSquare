inherit "thirdsquare.pike";

constant server_ip = "127.0.0.1", server_port = 5000;
mapping(int:function) services=([0|HOGAN_UDP:decode_packet]);

//IDs that we're awaiting responses for (mapped to [retry_count, data])
mapping(int:array(int|string)) awaiting=([]);
//Retry for a maximum of ten minutes before giving up. If a bus stops for ten mins in a dead spot, we have a problem.
//Note that the server uses actual time of receipt to handle ticketing, rather than an embedded timestamp; the retry
//loop could theoretically cause ticket extension, but only for touches-on, and frankly, if you're touching on THAT
//close to your ticket's expiry, it's not that big a surprise if it gets extended to daily.
constant retry_delay = ({2, 3, 5, 10, 15, 25, 60, 120, 120, 120, 120});

//For debugging, enable a console log of incoming packets
#define VERBOSE

object timer;

//Next targets. If this array is empty, our next target is 0 and touches-on are not accepted.
array(int) targets=({ });
int location; //Current location (possibly a location a bit ahead of us - touches are presumed to happen here)

//Called any time a card is touched to a reader.
//Will eventually result in a call to touch_result. Note that we kinda need a different touch_result for console and real touches.
void touch(int card)
{
}

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
	while (string cmd=Stdio.stdin.gets()) switch (lower_case((cmd/" ")[0]))
	{
		case "helo": timer = System.Timer(); sign_and_send_packet("HELO", server_ip, server_port); break;
		case "quit": exit(0);
		case "run":
		{
			array(string) termini=(cmd/" ")[1..];
			if (!sizeof(termini)) {write("USAGE: run terminus [terminus [terminus...]]\nStarts a run, setting the current terminus, and possibly more\ntermini after that. After the last, 0 is sent.\n"); break;}
			targets+=(array(int))termini;
			write("Current target: %d\nNext target: %d\n",targets[0],sizeof(targets)>1 && targets[1]);
			if (sizeof(targets)>2) write("%d additional targets after that.\n",sizeof(targets)-2);
			break;
		}
		case "loc":
		{
			sscanf(cmd,"loc %d",int loc);
			if (!loc) {write("USAGE: loc new_location\n"); break;}
			location=loc;
			write("We are now at location %d.\n",loc);
			if (sizeof(targets) && loc==targets[0])
			{
				targets=targets[1..];
				if (sizeof(targets)) write("Terminus! Our next target is: %d\n", targets[0]);
				else write("Terminus! End of the line, everybody off.\n");
			}
			break;
		}
		case "touch":
		{
			sscanf(cmd,"touch %d",int card);
			if (!card) {write("USAGE: touch cardid\n"); break;}
			touch(card);
			break;
		}
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
