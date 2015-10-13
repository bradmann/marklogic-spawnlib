xquery version "1.0-ml";

import module namespace trgr='http://marklogic.com/xdmp/triggers' at '/MarkLogic/triggers.xqy';
import module namespace spawnlib = "http://marklogic.com/spawnlib" at "/spawn/lib/spawnlib.xqy";

declare variable $trgr:uri as xs:string external := ();
declare variable $trgr:trigger as node() external;

(
	xdmp:log("SPAWNLIB DB ONLINE TRIGGER RUNNING!"),
	cts:search(
	  /spawnlib:job,
	  cts:element-range-query(
	    fn:QName("http://marklogic.com/spawnlib", "status"), 
	    "=", 
	    ("running", "initializing"),
	    "collation=http://marklogic.com/collation/codepoint"
	  )
	) ! xdmp:node-replace(./spawnlib:status, element spawnlib:status {"server shutdown"})
)