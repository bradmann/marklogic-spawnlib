# marklogic-spawnlib
Spawnlib is an XQuery library that provides [CoRB](https://github.com/marklogic/corb2)-like functionality in pure XQuery using the task server. The benefit of spawnlib is that it allows processing to occur across all nodes in the cluster, rather than one.

![](https://lh3.googleusercontent.com/-6QqJu3r7XMI/VeUT5HQTTkI/AAAAAAABZiI/LGTCYGO6JEI/s2048-Ic42/spawnlib.png)
 
Here's a "hello world" spawnlib job that can be run from qconsole:
```XQuery
xquery version "1.0-ml";
import module namespace spawnlib = "http://marklogic.com/spawnlib" at "/spawn/lib/spawnlib.xqy";

let $uris-query := '
	xquery version "1.0-ml";
	cts:uris((), (), cts:and-query(()))
'
let $xform-query := '
	xquery version "1.0-ml";
	declare variable $URI external;
	xdmp:log($URI)
'
let $options :=
	<options xmlns="xdmp:eval">
		<inforest>true</inforest>
		<appserver>spawnlib</appserver> <!-- Change this to the name of your appserver -->
		<authentication>
			<username>admin</username>
			<password>ML1234</password>
		</authentication>
		<result>true</result> <!-- This just means wait until the URIs query is complete before returning, otherwise the call below returns immediately -->
	</options>
return spawnlib:corb($uris-query, $xform-query, $options) 
```
NB: DISABLE THE REBALANCER BEFORE USING SPAWNLIB
