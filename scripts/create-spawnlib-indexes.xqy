xquery version "1.0-ml";

import module namespace admin = "http://marklogic.com/xdmp/admin" at "/MarkLogic/admin.xqy";

let $indexes := 
		<range-element-indexes xmlns="http://marklogic.com/xdmp/database">
			<range-element-index>
				<scalar-type>unsignedLong</scalar-type>
				<namespace-uri>http://marklogic.com/spawnlib</namespace-uri>
				<localname>total</localname>
				<range-value-positions>false</range-value-positions>
			</range-element-index>
			<range-element-index>
				<scalar-type>unsignedLong</scalar-type>
				<namespace-uri>http://marklogic.com/spawnlib</namespace-uri>
				<localname>job-id</localname>
				<range-value-positions>false</range-value-positions>
			</range-element-index>
			<range-element-index>
				<scalar-type>unsignedLong</scalar-type>
				<namespace-uri>http://marklogic.com/spawnlib</namespace-uri>
				<localname>host-id</localname>
				<range-value-positions>false</range-value-positions>
			</range-element-index>

			<range-element-index>
				<scalar-type>string</scalar-type>
				<namespace-uri>http://marklogic.com/spawnlib</namespace-uri>
				<localname>name</localname>
				<collation>http://marklogic.com/collation/codepoint</collation>
				<range-value-positions>false</range-value-positions>
			</range-element-index>
			<range-element-index>
				<scalar-type>string</scalar-type>
				<namespace-uri>http://marklogic.com/spawnlib</namespace-uri>
				<localname>status</localname>
				<collation>http://marklogic.com/collation/codepoint</collation>
				<range-value-positions>false</range-value-positions>
			</range-element-index>
			<range-element-index>
				<scalar-type>string</scalar-type>
				<namespace-uri>http://marklogic.com/spawnlib</namespace-uri>
				<localname>uri-query</localname>
				<collation>http://marklogic.com/collation/codepoint</collation>
				<range-value-positions>false</range-value-positions>
			</range-element-index>
			<range-element-index>
				<scalar-type>string</scalar-type>
				<namespace-uri>http://marklogic.com/spawnlib</namespace-uri>
				<localname>transform-query</localname>
				<collation>http://marklogic.com/collation/codepoint</collation>
				<range-value-positions>false</range-value-positions>
			</range-element-index>

			<range-element-index>
				<scalar-type>dateTime</scalar-type>
				<namespace-uri>http://marklogic.com/spawnlib</namespace-uri>
				<localname>created</localname>
				<range-value-positions>false</range-value-positions>
			</range-element-index>
			<range-element-index>
				<scalar-type>dateTime</scalar-type>
				<namespace-uri>http://marklogic.com/spawnlib</namespace-uri>
				<localname>completed</localname>
				<range-value-positions>false</range-value-positions>
			</range-element-index>
		</range-element-indexes>

let $config := admin:get-configuration()

let $_ :=	for $index in $indexes/*[fn:local-name(.) = 'range-element-index']
					let $_ := xdmp:log("working on " || $index//*:localname/fn:string())
					let $newconf :=
						try {
							admin:database-add-range-element-index($config, xdmp:database(), $index)
						} catch ($e) {
							if ($e//error:code eq "ADMIN-DUPLICATECONFIGITEM") then
								$config
							else
								(
								xdmp:log("This index could not be created: " || xdmp:quote($index) || " due to " || $e//error:code/fn:string()),
								$config
								)
						}
				return
					xdmp:set($config, $newconf)

let $_ := admin:save-configuration-without-restart($config)
return
	"Indexes successfully created"