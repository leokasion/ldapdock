 	<?php
	$host = $_SERVER['HTTP_HOST'];   // works for example.com or any LDAP_HOST
	$msg = '';
	
	if ($_SERVER['REQUEST_METHOD'] === 'POST') {
	    $uid = trim($_POST['uid'] ?? '');
	    $password = $_POST['password'] ?? '';
	
	    if ($uid && $password) {
	        $ldap = ldap_connect("ldap://127.0.0.1:389");
	        ldap_set_option($ldap, LDAP_OPT_PROTOCOL_VERSION, 3);
	        ldap_set_option($ldap, LDAP_OPT_REFERRALS, 0);
	
        // StartTLS required because your OpenLDAP enforces it
	        if (ldap_start_tls($ldap)) {
	            $bind_dn = "$uid,dc=example,dc=com";
	            if (@ldap_bind($ldap, $bind_dn, $password)) {
	                $msg = "<p style='color:green;font-weight:bold'>Login successful! Welcome $uid</p>";
	            } else {
	                $msg = "<p style='color:red'>Invalid credentials</p>$bind_dn";
	            }
	        } else {
	            $msg = "<p style='color:red'>TLS failure</p>";
	        }
	        ldap_close($ldap);
	    } else {
	        $msg = "<p style='color:red'>Please fill both fields</p>";
	    }
	}
	?>
	
	<!DOCTYPE html>
	<html>
	<head>
    <title>ldapdock LDAP login</title>
	    <style>
	        body { font-family: Arial, sans-serif; max-width: 400px; margin: 100px auto; text-align: center; }
	        input, button { padding: 10px; margin: 5px; width: 100%; font-size: 16px; }
	        button { background: #007cba; color: white; cursor: pointer; }
	    </style>
	</head>
	<body>
	    <h1>ldapdock login</h1>
	    <p>Server: <strong><?= htmlspecialchars($host) ?></strong></p>
	    <?= $msg ?>
	    <form method="post">
	        <input type="text" name="uid" placeholder="uid (e.g. marisa)" required autofocus><br>
	        <input type="password" name="password" placeholder="password" required><br>
	        <button type="submit">Login</button>
	    </form>
	    <hr>
	    <small>Test user: uid=marisa,ou=People / MarisaNewPass2025</small>
	</body>
	</html>
