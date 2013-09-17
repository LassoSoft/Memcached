<?lasso

//============================================================================
//
//	Extend null
//
//............................................................................		

define null->asinteger => { return integer(self) }
define null->asdecimal => { return decimal(self->asstring) }

//============================================================================
//
//	Fix JSON — The Vinilla Lasso JSON methods fails in a couple of areas.
//
//				1.	You can only decode the same bytes once before it errors
//				2.	Consume token did no take into account closing arrays
//
//............................................................................		

define json_consume_token(ibytes::bytes, temp::integer) => {

	local(obytes = bytes->import8bits(#temp) &,
		delimit = array(9, 10, 13, 32, 44, 58, 93, 125)) // \t\r\n ,:]}

	while(#delimit !>> (#temp := #ibytes->export8bits))
		#obytes->import8bits(#temp)
	/while

	#temp == 125? // }
		#ibytes->marker -= 1
//============================================================================
//	Is also end of token if end of array[]
	#temp == 93? // ]
		#ibytes->marker -= 1
//............................................................................		

	local(output = string(#obytes))
	#output == 'true'?
		return true
	#output == 'false'?
		return false
	#output == 'null'?
		return null
	string_IsNumeric(#output)?
	return (#output >> '.')? decimal(#output) | integer(#output)

	return #output
}

define json_deserialize(ibytes::bytes)::any => {
	#ibytes->removeLeading(bom_utf8);

//============================================================================
//	Reset marker on provided bytes
	#ibytes->marker = 0
//............................................................................		
	
	Local(temp) = #ibytes->export8bits;
	If(#temp == 91); // [
		Return(json_consume_array(#ibytes));
	Else(#temp == 123); // {
		Return(json_consume_object(#ibytes));
	else(#temp == 34) // "
		return json_consume_string(#ibytes)
	/If;
}

//============================================================================
//
//	Error codes & messages
//
//............................................................................		

define error_code_memcached_servers_not_set => -20001
define error_msg_memcached_servers_not_set  => `No memcached servers set, set using: memcached_servers = array('127.0.0.1')`

define error_code_memcached_no_servers 		=> -20002
define error_msg_memcached_no_servers  		=> `No memcached servers specified, specify using: memcached(array('127.0.0.1'))`

define error_code_memcached_offline 		=> -20003
define error_msg_memcached_offline 			=> `No memcached servers available.`

define error_code_memcached_missingblock 	=> -20004
define error_msg_memcached_missingblock 	=> `No block provided, specify using: memcached('key') => '[date] cached' `

define error_code_memcached_unknowntype		=> -20005
define error_msg_memcached_unknowntype 		=> `Unknown data type, key set by another client?`

define error_code_memcached_invalidkey		=> -20006
define error_msg_memcached_invalidkey 		=> `Invalid key, must be alphanumeric and contain no whitespace.`

//============================================================================
//
//	Lasso instance wide settings:
//
//		memcached_server = '127.0.0.1'
//		memcached_servers = array('127.0.0.1','127.0.0.2')
//
//............................................................................		

define memcached_server=(server::string) => { memcached_servers = array(#server) }
define memcached_servers=(servers::array) => {
	admin_setPref('lasso_memcached_servers',#servers->join(','))
	var(_memcached_servers) = #servers
}
define memcached_servers => {
	var(_memcached_servers) ? return $_memcached_servers
	local(servers) = admin_getPref('lasso_memcached_servers')
	return $_memcached_servers := (#servers ? #servers->asstring->split(',') | array)
}

//============================================================================
//
//	memcached — returns thread based memcached_type
//
//............................................................................		

define memcached => {
	var(_memcached) ? return $_memcached
	fail_if(
		!memcached_servers->size,
		error_code_memcached_servers_not_set,
		error_msg_memcached_servers_not_set
	)
	return $_memcached := memcached_type(memcached_servers)
}

//============================================================================
//
//	memcached(array) — returns local memcached_type
//
//............................................................................		

define memcached(servers::array) => {
	fail_if(
		!#servers->size,
		error_code_memcached_no_servers,
		error_mesg_memcached_no_servers
	)
	return memcached_type(#servers)
}

//============================================================================
//
//	User friendly, thread based calls: (uses lasso settings)
//
//		memcached(#key,#expires) => 'Item to cache'
//
//............................................................................		

define memcached(key::string,expires::integer=0,forcerefresh::boolean=false) => {
	local(
		m = memcached,
		gb = givenblock,
		val
	)
	
	//	Check for given block
	fail_if( 
		#gb->isa(::void), 
		error_code_memcached_missingblock,
		error_msg_memcached_missingblock
	)
	
	//	Check for item in cache
	if(!#forcerefresh) => {
		#val = #m->get(#key)
		#val->isnota(::void)
		? return #val
	}

	//	Process supplied block
	match(#gb->type) => {
		case(::file)
			local(
				b = #gb->readBytes,
				enc = #b->bestCharset('UTF-8') 
			)
			#val = sourcefile(#b->exportAs(#enc),file_forceRoot(#gb->path),true,true)()
		case(::string)
			#val = sourcefile(#gb,'memcache_'+#key,true,true)()
		case(::capture)
			#gb->detach
			#val = #gb()
		case
			#val = #gb
	}

	//	Store result
	#m->set(#key,#val,#expires)
	
	//	Return result
	return #val;
}

define memcached(key::string,refresh::boolean) => memcached(#key,0,#refresh) => givenblock
define memcached(key::string,expires::date) => memcached(#key,#expires->asinteger) => givenblock

//============================================================================
//
//	memcached_server 
//
//		Used to gracifully handle offline servers
//
//............................................................................		

define memcached_server => type {
	data 
		public name::string,
		public port::integer,
		public connection = void
		
	public oncreate(name::string,port::integer=11211) => {
		.name = #name
		.port = #port
	}

	public oncompare(p::memcached_server) => {
		#p->name == .name && #p->port == .port ? return 0
		return (#p->name+#p->port) > (.name+.port) ? -1 | 1
	}

	public asstring => .name + ':' + .port

	public connection => {
		.'connection'->isnota(::void)
		? return .'connection'

		local(
			i = 0,
			net = net_tcp
		)

		#net->connect(.name,.port,1)
		? return .'connection' := #net
		| return .'connection' := null

	}
}

//============================================================================
//
//	core memcached_type
//
//............................................................................		

define memcached_type => type {
	data 
		private servers = array,
		public graceful::boolean = true,
		public readtimeout::integer=1
	
	public oncreate(servers::array) => {
		with server in (#servers->sort &) do {
			.servers->insert(
				#server >> ':'
				? memcached_server(#server->split(':')->first,#server->split(':')->last->asinteger)
				| memcached_server(#server,11211)
			)			
		}
	}
	
	private index(key::string,servers::array=.servers) => (bytes(#key)->crc % #servers->size) + 1
	private server(key::string) => .server(.index(#key))		
	private server(i::integer) => {
		local(server) = .servers->get(#i)

		// Check if server online — otherwise failover to first available server
		if(!#server->connection && .servers->size > 1) => {
			with s in .servers do {
				if(#s->connection) => {
					return #s
				}
			}
		}
		
		return #server
	}

	private store(cmd::string,key::string,value::string,expires::integer=0,flags::integer=0,cas::integer=0)::string => {
	
		//	Get connection
		local(c) = .server(#key)->connection
		
		//	Be graceful on error
		if(!#c) => {
			fail_if(!.graceful,error_code_memcached_offline,error_msg_memcached_offline)
			return ''
		}
		
		//	Write command to server
		#c->writebytes(
			bytes(
				#cmd + ' ' + 
				#key + ' ' + 
				#flags + ' ' + 
				#expires  + ' ' + 
				#value->size + 
				(#cas ? ' ' + #cas) +
				'\r\n' + #value + '\r\n'
       		)
		)
		
		//	Return raw result
		return #c->readSomeBytes(1024*1024,.readtimeout)->asstring
	}

	private retrieve(server::memcached_server,cmd::string,keys::string,asmap::boolean=false)::map => {	
		local(
			c = #server->connection,
			results = map,
			blob=bytes,
			delim = bytes('\r\n'),
			index,
			length,
			info,
			type,
			key,
			cas,
			value
		)

		//	Be graceful on error
		if(!#c) => {
			fail_if(!.graceful,error_code_memcached_offline,error_msg_memcached_offline)
			return map
		}

		// Issue command
		#c->writebytes(
			bytes(
				#cmd + ' ' + 
				#keys +
				'\r\n'
       		)
		)
		
		local(i=0)
		while(!#blob->endswith('END\r\n') && #i++ < 10) => {
			#blob->append(#c->readSomeBytes(1024*1024,.readtimeout))
		}
		
		with i in 1 to #keys->split(' ')->size do {			
			#index 	= #blob->find(#delim)
			#info 	= #blob->sub(1,#index)->split(' ')
	
			if((:4,5) >> #info->size == 4) => {

				#key	= #info->get(2)
				#type 	= integer(#info->get(3))
				#length	= integer(#info->get(4))
				#cas	= ( #info->size == 5 ? #info->get(5)->asinteger | 0)
				
				
				// trim blob (account for find)
				#blob->remove(1,#index + 1)
				
				// extract value
				#value = #blob->sub(1,#length)
			
				// trim blog (account for delim)
				#blob->remove(1,#length+2)
				
				if(#asmap) => {
					#results->insert(
						#key = map(
							'key' = #key,
							'value' = #value,
							'type' = .decode(#value,#type),
							'cas' = #cas
						)
					
					)				
				else
					#results->insert(
						#key->asstring = .decode(#value,#type)
					)
				}
				
			}
		}
		
		return #results
	}

	private issue(server::memcached_server,cmd::string)::string => {
		local(
			c = #server->connection,
			out=map,blob,info
		)		

		//	Be graceful on error
		if(!#c) => {
			fail_if(!.graceful,error_code_memcached_offline,error_msg_memcached_offline)
			return ''
		}

		//	Write command
		#c->writebytes(
			bytes(
				#cmd + '\r\n'
       		)
		)
		
		//	Return raw result
		return #c->readSomeBytes(1024*1024,1)->asstring
	}
	
	private key(p::string) => {
		local(i=1,o=#p->size)	
		with b in bytes(#p)->eachbyte do {
			#b > 32 && #b < 127 ? #i++ | #p->remove(#i,1)
		}
		!.graceful
		? fail_if(#p->size != #o || !#p->size,error_code_memcached_invalidkey,error_msg_memcached_invalidkey)
		return #p
	}
	
	public set(key::string,value::any,expires::integer=0) => {
		return .store('set',.key(#key),.encode(#value),#expires,.flag(#value))
	}

	public set(pair::pair,expires::integer=0) => .set(#pair->name,#pair->value,#expires)
	
	public append(key::string,value::any,expires::integer=0) => {
		return .store('append',.key(#key),.encode(#value),#expires,.flag(#value))
	}

	public prepend(key::string,value::any,expires::integer=0) => {
		return .store('prepend',.key(#key),.encode(#value),#expires,.flag(#value))
	}
		
	public cas(key::string,value::any,cas::integer,expires::integer=0) => {
		return .store('cas',.key(#key),.encode(#value),#expires,.flag(#value),#cas)
	}

	public get(key::string) => .retrieve(.server(.key(#key)),'get',#key)->find(#key)
	
	public get(keys::array,asmap::boolean=false) => {
	
		//	Ensure each key is requested from the correct server
		//	Batch request multiple keys from same server
		
		local(
			requests = map,
			request,
			results = map,
			result,
			i
		)
		
		//	Build requests for each server
		with key in #keys do {
			#i = .index(.key(#key))
			#requests !>> #i ? #requests->insert(#i=array)
			#requests->find(#i)->insert(#key)
		}
		
		//	Call each server
		with i in #requests->keys do {
			
			//	Check for keys
			#request = #requests->find(#i)
			
			if(#request->size) => {
			
				//	Get result
				#result = .retrieve(
								.server(#i),
								'gets',
								#request->join(' '),
								#asmap
						   )
				//	Merge results
				with key in #result->keys do {
					#results->insert(
						#key = #result->find(#key)
					)
				}	
			}
		}
		
		return #results
	}

	public delete(key::string) => .issue(.server(#key),'delete ' + #key) >> 'DELETED'

	public incr(key::string,value::integer=1) => .issue(.server(#key),'incr ' + #key + ' ' + #value)->asinteger
	public decr(key::string,value::integer=1) => .issue(.server(#key),'decr ' + #key + ' ' + #value)->asinteger

	public touch(key::string,expires::integer) => .issue(.server(#key),'touch ' + #key + ' '+#expires)//->asinteger
	public touch(key::string,expires::date) => .touch(#key,#expires->asinteger)

	public flush(opt::string='') => {
		local(r) = true
		with server in .servers do {
			.issue(#server,'flush_all' + #opt) !>> 'OK' ? #r = false
		}
		return #r
	}
	
	public flush(expires::integer) => .flush(' '+#expires)
	public flush(expires::date) => .flush(' '+#expires->asinteger)

	public version => decimal(.versions->first->value->split('.')-> insert('.',2) & join)

	public versions => {
		local(r) = array
		with server in .servers do {
			#r->insert(
				#server->asstring = .issue(#server,'version')->split(' ')->last->trim &
			)
		}
		return #r
	}
	
	public stats => {
		local(out=map,stats)
		with s in .servers do {
			#stats = map
			with line in .parse(
				.issue(#s,'stats'),3
			) do {
				#stats->insert(
					#line->get(2) = #line->get(3)
				)
			}
			#out->insert(
				#s->name = #stats
			)
		}
		return #out
	}
	
	public status::string => {
		local(
			online  = 0,
			offline = 0
		)
		with status in .serverstatus do {
			#status == 'online'
			? #online += 1
			| #offline += 1
		}
		
		if(#online > 0 && #offline == 0) => {
			return 'online'
		else(#online > 0 && #offline > 0)
			return 'degraded'
		else
			return 'offline'
		}
	}

	public serverstatus => {
		local(out) = map
		with server in .servers do {
			#out->insert(
				#server->asstring = (#server->connection ? 'online' | 'offline')
			)
		}
		return #out
	}

	private parse(result::string,keys::integer) => {
		local(out=array)
		with line in #result->split('\r\n') do {
			#line = #line->split(' ')
			#line->size == #keys 
			? #out->insert(#line)
		}
		return #out
	}

	private flag(p::any) => {
		match(#p->type) => {
			case(::pair)
				return 9
			case(::map)
				return 8
			case(::array)
				return 7
			case(::date)
				return 6
			case(::string)
				return 5
			case(::decimal)
				return 4
			case(::integer)
				return 3
			case(::null)
				return 2
			case(::void)
				return 1
			case
				return 0
		}
	}

	private encode(value::any) => {
		match(#value->type) => {
			case(::bytes)
				return #value->encodebase64->asstring
			case(::array)
				return json_serialize(#value)
			case(::pair)
				return json_serialize(#value)
			case(::map)
				return json_serialize(#value)
			case(::date)
				return #value->asinteger->asstring
			case
				return #value->asstring
		}		
	
		return bytes(#value)
	}

	private decode(value::any,flag::integer) => {	
		match(#flag) => {
			case(0)
				return #value->decodebase64
			case(9)
				local(a) = json_deserialize(#value->asstring)
				return pair(#a->get(1) = #a->get(2))
			case(8)
				return json_deserialize(#value->asstring)
			case(7)
				return json_deserialize(#value->asstring)
			case(6)
				return date(#value->asinteger)
			case(5)
				return #value->asstring
			case(4)
				return #value->asdecimal
			case(3)
				return #value->asinteger
			case(2)
				return null
			case(1)
				return void
			case
				fail(error_code_memcached_unknowntype,error_nsg_memcached_unknowntype)
				return #value
		}
	}
}

//============================================================================
//
//	memcached_type testsuite
//
//............................................................................		

define memcached_tests(server::string) => {

	local(m) = memcached_type(array(#server))

	handle => {
		#m->delete('pair')
		#m->delete('map')
		#m->delete('array')
		#m->delete('date')
		#m->delete('string')
		#m->delete('decimal')
		#m->delete('integer')
		#m->delete('null')
		#m->delete('void')
		#m->delete('bytes')
	}
	
	//	Turn off graceful mode
	#m->graceful = false

	#m->set('pair'=pair('a'=4))
	#m->set('map'=map('a'=1,'b'=2,'c'=3))
	#m->set('array'=array(1,2,3))
	#m->set('date'=date('2001-12-24 00:00:01'))
	#m->set('string'='This is a test')
	#m->set('decimal'=2.1)
	#m->set('integer'=1)
	#m->set('null'=null)
	#m->set('void'=void)
	#m->set('bytes'=bytes('000'))
	
	// Validate types
	fail_if(#m->get('pair')->isnota(::pair),-1,'Failed to store/retrive pair')
	fail_if(#m->get('map')->isnota(::map),-1,'Failed to store/retrive map')
	fail_if(#m->get('array')->isnota(::array),-1,'Failed to store/retrive array')
	fail_if(#m->get('date')->isnota(::date),-1,'Failed to store/retrive date type')
	fail_if(#m->get('string')->isnota(::string),-1,'Failed to store/retrive string')
	fail_if(#m->get('decimal')->isnota(::decimal),-1,'Failed to store/retrive decimal')
	fail_if(#m->get('integer')->isnota(::integer),-1,'Failed to store/retrive integer')
	fail_if(#m->get('null')->isnota(::null),-1,'Failed to store/retrive null')
	fail_if(#m->get('void')->isnota(::void),-1,'Failed to store/retrive void')
	fail_if(#m->get('bytes')->isnota(::bytes),-1,'Failed to store/retrive bytes')
	
	//	Validate data
	fail_if(#m->get('pair')->value != 4,-1,'Pair returned incorrect value')
	fail_if(#m->get('map')->find('a') != 1,-1,'Map returned incorrect value')
	fail_if(#m->get('array')->get(3) != 3,-1,'Array returned incorrect value')
	fail_if(#m->get('array')->size != 3,-1,'Array returned incorrect size')
	fail_if(#m->get('date')->year != 2001,-1,'Date returned incorect year')
	fail_if(#m->get('string') != 'This is a test',-1,'String returned inncorrect value')
	fail_if(#m->get('decimal') != 2.1,-1,'Decimcal returned incorrect value')
	fail_if(#m->get('integer') != 1,-1,'Integer returned incorrect value')
	fail_if(#m->get('null') != null,-1,'Null returned incorrect value')
	fail_if(#m->get('void') != void,-1,'Void returned incorrect value')
	fail_if(#m->get('bytes') != bytes('000'),-1,'Bytes returned incorrect value')	
	
	//	Valiate commands
	fail_if(#m->append('string','_END') & get('string') != 'This is a test_END','Failed to append string')
	fail_if(#m->prepend('string','START_') & get('string') != 'START_This is a test_END','Failed to prepend string')
	fail_if(#m->incr('integer',2) != 3,'Increment failed to increase value')
	fail_if(#m->decr('integer') != 2,'Decrement failed to decrease value')

	//	Touch command is only valid on the latest memcache servers (1.4.8)
	if(#m->version >= 1.48) => {
		fail_if(#m->touch('integer',10) != 10,'Failed to touch key')
	}

	fail_if(!#m->delete('integer'),'Could not delete key')
	fail_if(!#m->version,'Could not get version')
	fail_if(#m->stats->isnota(::map),'Stats did not return an map')
	fail_if(#m->stats->size != 1,'Stats did not return a valid map')
	
//============================================================================
//
//	Check user friendly mode
//
//............................................................................		

	//	Overwrite thread var
	var(_memcached_servers) = array(#server)
	
	//	Create test file
	local(file) = file('./memcache.test')
	! #file->exists ? #file->writeBytes(bytes('[date]'))

	handle => {
		memcached->delete('test_capture_integer')
		memcached->delete('test_capture_array')
		memcached->delete('test_string')
		memcached->delete('test_file')
	}

	//	Test captures
	memcached('test_capture_integer') => { return 1 + 2 }
	memcached('test_capture_array') => { return array(1,2,3) }
	memcached('test_string') => '[date]'
	memcached('test_file') => #file

	fail_if(#m->get('test_capture_integer') != 3,-1,'test_capture_integer failed returned incorrect value')
	fail_if(#m->get('test_capture_array')->isnota(::array),-1,'test_capture_array failed returned incorrect type')
	fail_if(#m->get('test_capture_array')->size != 3,-1,'test_capture_array failed returned incorrect size')
	fail_if(#m->get('test_string') !>> date->year->asstring,-1,'test_string does not contain current year')
	fail_if(#m->get('test_file') !>> date->year->asstring,-1,'test_string does not contain current year')
	
	//	Test overwrite	
	memcached('test_string',true) => 'Hello'
	fail_if(#m->get('test_string') !>> 'Hello',-1,'test_string was not correctly replaced')

	//	Test expiry
	memcached('test_expiry',2) => 'old'
	memcached('test_expiry',2) => 'new'
	
	fail_if(#m->get('test_expiry') != 'old',-1,'test_expiry expired too quickly')	

	sleep(2500)
	memcached('test_expiry',2) => 'new'
	fail_if(#m->get('test_expiry') != 'new',-1,'test_expiry did not expire')
	
	return 'OK: All tests ran successfully'

}
?>