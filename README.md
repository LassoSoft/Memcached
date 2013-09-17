Memcached for Lasso 9
=====================

Intuitive Memcached client for Lasso 9 — supports single / multiple servers.

Written by Ke Carlton, Zeroloop

Published with permission by LassoSoft Inc

What is Memcached?
------------------

Free & open source, high-performance, distributed memory object caching system, generic in nature, but intended for use in speeding up dynamic web applications by alleviating database load.
Memcached is an in-memory key-value store for small chunks of arbitrary data (strings, objects) from results of database calls, API calls, or page rendering.
Memcached is simple yet powerful. Its simple design promotes quick deployment, ease of development, and solves many problems facing large data caches.
More information about Memcached can be found online http://www.memcached.org/

Lasso Memcached Client
--

The Lasso 9 Memcached client supports multiple Memcached servers, automatic server redundancy + fail over, native object storage + retrieval — and is simple to use.

Getting started
===============

It’s best to run Memcached on a dedicated virtual machine as most of the available memory will be used by Memcached. Depending on throughput, a VM with1GB memory should be a good starting point.

Install Memcached
--

Download and install memcached for your appropriate platform:

Ubuntu / Redhat / Centos:
http://code.google.com/p/memcached/wiki/NewInstallFromPackage

OSX:
http://www.google.com/search?q=memcached+osx+install



Configure Lasso
===============
To configure Lasso for Memcached simply specify your Memcached server(s). 
These settings are unique to each Lasso Instance:

    ￼memcached_server = '127.0.0.1'

or

    ￼memcached_servers = array(
      '192.168.1.25:11211',
      '192.168.1.26:11211'
    )
    
Test your Memcached servers:

    ￼memcached->serverstatus



Simple syntax
=============
Once your server test returns online for all servers you can start to use Memcached. The syntax is very simple and utilises Lasso’s blocks:

    ￼memcached('string_example') => 'I was cached on [date].'
    memcached('include_example') => file('/file/to/include.inc')
    memcached('capture_example') => { return array(1,2,3) }

Supported blocks
--

The given block should be a string, file or capture. Captures should return the value to store when they are invoked. Strings and files are compiled and invoked as Lasso source code. Each block is only invoked if a valid key is not present in the cache.

Supported types
--

The core Lasso types are automatically encoded and decoded when they are stored and retrieved from Memcached. The types supported are: null, integer, decimal, string, bytes, pair, array and map.

Graceful mode
--

By default the Memcached client runs in a graceful mode — this means that errors are suppressed and the cached will be skipped if no Memcached servers are unavailable or similar. During development you may find it useful to disable graceful mode:

    ￼memcached->graceful = false



Expiration
--

You can specify an expiration value in seconds or as a date object.

    ￼memcached('expire_60_seconds',60) => 'I was cached on [date].'
    memcached('expire_tomorrow',date) => 'I was cached on [date].'

You can also force memcached to refresh the cached item by specify a boolean parameter.

    ￼memcached('force_refresh',true) => 'I was cached on [date].'

or

    ￼memcached('force_refresh',60,true) => 'I was cached on [date].'

Real world examples
===================

The simplest way of handling expiration is to use a revision value as part of the key. In the below example the CMS system sets a variable $revision that represents the last date/time the sites content was changed.

    ￼memcached('mainmenu_' + $revision) => file('/includes/mainmenu.inc')

The following example caches all of a users friends for 10 minutes.

    ￼memcached('friends_' + user_id,600) => { return current_user->friends }

This example caches a view of a user’s cart. The values of user_id and cart_version are stored in the user session. When the user modifies their cart, cart_version is updated and the view is re-cached.

    ￼memcached('usercart_' + user_id + '_' + cart_version) => file(
        '/includes/smallcart.inc'
    )

Old items simply drop out of memcached as newer items take the space. Working with unique keys is the simplest way of managing the cache — it’s much easier than trying to manually expire items.

Working directly with Memcached
===============================

The Lasso client for Memcached also supports all the standard memcached calls — each command is documented at the end of this document. They can be access like so:

    ￼memcached->command(parameters)

The memcached client can also be used locally:

    ￼local(memcached) = memcached(array('127.0.0.1'))



Standard Commands
=================

The Lasso memcached client also supports all standard Memcached commands. These can be utilized if you'd like to work with Memcached directly.

set
---

set(key::string,value::any,expires::integer=0)::boolean 
set(key::string,value::any,expires::date)::boolean

Store the specified value:

    ￼memcached->set('mykey','my val)

get
---

get(key::string)::any get(keys::array,asmap::boolean=false)::map

Retrieve the specified key(s) from the server.

Returns either the value or a map containing the results if multiple keys are specified:

    ￼memcached->get('mykey')
    memcached->get(array('mykey','anotherkey'))
    
    
append
---

append(key::string,value::any,expires::integer=0)::boolean

Append to value to an existing key.

    ￼memcached->append('mykey','append

prepend
--
prepend(key::string,value::any,expires::integer=0)::boolean

Prepend to value to an existing key.

    ￼memcached->prepend('mykey','prepend 

cas (check and set)
--
cas(key::string,value::any,cas::integer,expires::integer=0)::boolean

Store the specified value only if it hasn't change since last retrieved. Use the cas parameter provided by gets(array,true) to make this call.

    ￼￼￼memcached->cas('mykey','new value',12345)

delete
--
delete(key::string)::boolean

The command "delete" allows for explicit deletion of items

    ￼memcached->delete('mykey')

incr
--
incr(key::string,value::integer=1)::integer

Increment the specified key by the value — key must exist. Returns new integer value.

    ￼memcached->incr('mykey')

decr
--
decr(key::string,value::integer=1)::integer

Decrement the specified key by the value — key must exist. Returns new integer value.

    ￼memcached->decr('mykey',1)

touch
--
touch(key::string,expires::integer)::boolean 
touch(key::string,expires::date)::boolean

Reset the expiration time on a key — key must exist. Supported by Memcached version 1.4.8 and greater. Returns boolean

    memcached->touch('mykey',60)

flush
--
flush::boolean 
flush(expires::integer)::boolean 
flush(expires::date)::boolean

Flush the cach of all key or keys due to expire after specific value. Returns boolean.

    ￼memcached->flush

version
--
Returns the version of the first specified server.

versions
--
Returns a map contain the version of each server.

Credits
==
Written by Ke Carlton, Zeroloop

Published with permission by LassoSoft Inc.

http://www.lassosoft.com/
