{% import 'redirected_uri_extra.tpl' as redirected_uri_extra with context %}
{% import 'backed_uri_extra.tpl' as backed_uri_extra with context %}
{% if hook_server_configuration.additional_log_formats %}
#  HOOK- : {{ hook_server_configuration.additional_log_formats.path }}
{% include hook_server_configuration.additional_log_formats.path with context %}
# -HOOK  : {{ hook_server_configuration.additional_log_formats.path }}
{% endif %}

log_format access_{{ server }}-{{ port }} '$remote_addr - $remote_user [$time_local] "$request" '
                 '$status $body_bytes_sent "$http_referer" '
                 '"$http_user_agent" "$scheme://$host:$server_port$request_uri" $request_time';

log_format backend_failed_{{ server }}-{{ port }} '$remote_addr [$time_local] '
                 '$status $body_bytes_sent $request_time "$scheme://$host:$server_port$request_uri" '
                 '"$http_referer"';

{% for upstream in upstream_configuration -%}
{% if not upstream.ips -%}
# IMPOSSIBLE DE RESOUDRE {{ upstream.host }} POUR {{ upstream.name }}
# TODO - IMPLEMENTER UN SERVEUR TECHNIQUE INDIQUANT QUE LE DNS N'EST PAS RESOLVABLE

{% else %}
{% for client_http_connect in extra_from_distrib_configurations.backed_uri_extra.properties.client_http_connect.enum -%}
{% for balanced_sticky_style in ( extra_from_distrib_configurations.backed_uri_extra.properties.balanced_sticky_style.enum if upstream.reversed_names|length > 1 else [ '' ] ) -%}
{% for reversed_name in ( upstream.reversed_names.keys()|sort if upstream.reversed_names|length > 1 and balanced_sticky_style != '' else [ upstream.reversed_names.keys()[ 0 ] ] ) -%}
upstream {{ upstream.name }}{%if balanced_sticky_style %}_with_balanced_sticky_{{ balanced_sticky_style }}_for_{{ reversed_name }}{% endif %}_with_connect_defined_to_{{ client_http_connect }} {
    # resolution de upstream {{ upstream.name }}{%if balanced_sticky_style %}_with_balanced_sticky_{{ balanced_sticky_style }}_for_{{ reversed_name }}{% endif %}_with_connect_defined_to_{{ client_http_connect }} valide au rafraichissement de FS
    {% for ip in upstream.ips|sort -%}
    server {{ ip }}:{{ upstream.port }} {% if ip not in upstream.reversed_names[ reversed_name ] and balanced_sticky_style %}backup{% endif %};		# {{ upstream.reversed_ips[ ip ] }}
    {% endfor -%}
    {% if client_http_connect == "" -%}
    keepalive 16;
    {% endif -%}
}

{% endfor -%}
{% endfor -%}
{% endfor -%}

{% for client_http_connect in ( extra_from_distrib_configurations.backed_uri_extra.properties.client_http_connect.enum if upstream.reversed_names|length > 1 else [] ) -%}
{% for balanced_sticky_style in ( extra_from_distrib_configurations.backed_uri_extra.properties.balanced_sticky_style.enum if upstream.reversed_names|length > 1 else [] ) -%}
{% for scheme in ( [ 'http', 'https' ] if balanced_sticky_style != '' else [] ) -%}
map $route_cookie_jsessionid_{{ suffix_map }} $upstream_{{ upstream.name }}_with_scheme_defined_to_{{ scheme }}_with_balanced_sticky_defined_to_{{ balanced_sticky_style }}_with_connect_defined_to_{{ client_http_connect }} {
    default {{ scheme }}://{{ upstream.name }}_with_connect_defined_to_;
    {% for reversed_name in ( upstream.reversed_names.keys()|sort if upstream.reversed_names|length > 1 and balanced_sticky_style != '' else [] ) -%}
    ~*^{{ reversed_name }}$ {{ scheme }}://{{ upstream.name }}_with_balanced_sticky_{{ balanced_sticky_style }}_for_{{ reversed_name }}_with_connect_defined_to_;
    {% endfor -%}
}

{% endfor -%}
{% endfor -%}
{% endfor -%}
{% endif -%}
{% endfor -%}

server {

    {% if hook_server_configuration.to_server_beginning %}
    #  HOOK- : {{ hook_server_configuration.to_server_beginning.path }}
    {% include hook_server_configuration.to_server_beginning.path with context %}
    # -HOOK  : {{ hook_server_configuration.to_server_beginning.path }}
    {% endif %}

    server_tokens 		off;

    underscores_in_headers      on;

    {% for nameserver in resolver.nameservers -%}
    resolver 			{{ nameserver }};
    {% endfor -%}

    {% for r in resolver.query( server, 'A' ) -%}
    listen   			{{ r.address }}:{{ port }}{% if ssl_configuration %} ssl{% endif -%};
    {% endfor -%}
    {% for r in resolver.query( server, 'AAAA' ) -%}
    listen   			[{{ r.address }}]:{{ port }} ipv6only=on{% if ssl_configuration %} ssl{% endif -%};
    {% endfor -%}

    {% if ssl_configuration -%}
    ssl_certificate 		{{ ssl_configuration.ssl_certificate_filepath }};
    ssl_certificate_key		{{ ssl_configuration.ssl_certificate_key_filepath }};

    ssl_session_cache shared:SSL:1m;
    ssl_session_timeout  5m;

    ssl_ciphers  HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers   on;

    {% endif -%}

    {% if hook_server_configuration.additional_access_logs %}
    #  HOOK- : {{ hook_server_configuration.additional_access_logs.path }}
    {% include hook_server_configuration.additional_access_logs.path with context %}
    # -HOOK  : {{ hook_server_configuration.additional_access_logs.path }}
    {% endif %}
    access_log 			/var/log/nginx/.{{ server }}-{{ port }}.access.log access_{{ server }}-{{ port }};
    error_log 			/var/log/nginx/.{{ server }}-{{ port }}.error.log info;
     

    error_page                  404     =404       /__NO_CONFIGURATION__.html;
    error_page                  502     =503       /__BACKEND_FAILED__.html;
    error_page                  504     =503       /__BACKEND_FAILED__.html;
    error_page                  418     =503       /__NO_RESOLUTION_FOR_BACKEND__.html;

    root /home/z00_www_static/;

    location / {

        set $original_uri $uri;

        root /home/z00_www_static/;


        location = /{{ random_id( 12 ) }}__STATUS__{{ random_id( 12 ) }} {

            stub_status on;

        }

        location = /__BACKEND_FAILED__.html {
            internal;

            access_log  /var/log/nginx/.{{ server }}-{{ port }}.backend_failed.log backend_failed_{{ server }}-{{ port }};

            try_files 	/{{server}}/{{port}}/$url_2_entity_{{ suffix_map }}/$host/$uri
                        /{{server}}/{{port}}/$url_2_entity_{{ suffix_map }}/__default__/$uri
                        /{{server}}/__default__/$url_2_entity_{{ suffix_map }}/$host/$uri
                        /{{server}}/__default__/$url_2_entity_{{ suffix_map }}/__default__/$uri
                        /{{server}}/{{port}}/__default__/$host/$uri
                        /{{server}}/{{port}}/__default__/__default__/$uri
                        /{{server}}/__default__/__default__/$host/$uri
                        /{{server}}/__default__/__default__/__default__/$uri
                        /__default__/__default__/__default__/$host/$uri
                        /__default__/__default__/__default__/__default__/$uri
                        =404;

        }

        location = /__NO_CONFIGURATION__.html {
            internal;

            try_files   /{{server}}/{{port}}/$url_2_entity_{{ suffix_map }}/$host/$uri
                        /{{server}}/{{port}}/$url_2_entity_{{ suffix_map }}/__default__/$uri
                        /{{server}}/__default__/$url_2_entity_{{ suffix_map }}/$host/$uri
                        /{{server}}/__default__/$url_2_entity_{{ suffix_map }}/__default__/$uri
                        /{{server}}/{{port}}/__default__/$host/$uri
                        /{{server}}/{{port}}/__default__/__default__/$uri
                        /{{server}}/__default__/__default__/$host/$uri
                        /{{server}}/__default__/__default__/__default__/$uri
                        /__default__/__default__/__default__/$host/$uri
                        /__default__/__default__/__default__/__default__/$uri
                        =404;

        }

        location = /__NO_RESOLUTION_FOR_BACKEND__.html {
            internal;
            ssi on;

            try_files   /{{server}}/{{port}}/$url_2_entity_{{ suffix_map }}/$host/$uri
                        /{{server}}/{{port}}/$url_2_entity_{{ suffix_map }}/__default__/$uri
                        /{{server}}/__default__/$url_2_entity_{{ suffix_map }}/$host/$uri
                        /{{server}}/__default__/$url_2_entity_{{ suffix_map }}/__default__/$uri
                        /{{server}}/{{port}}/__default__/$host/$uri
                        /{{server}}/{{port}}/__default__/__default__/$uri
                        /{{server}}/__default__/__default__/$host/$uri
                        /{{server}}/__default__/__default__/__default__/$uri
                        /__default__/__default__/__default__/$host/$uri
                        /__default__/__default__/__default__/__default__/$uri
                        =404;

        }

    {% if converted_unmount_map_filename in list_converted_map_filenames %}
        if ( $not_mapped_{{ suffix_map }} ) {
             return 		404;
        }
    {% else %}
        # Pas de configuration unmap pour ce serveur
    {% endif -%}

    {% if converted_redirect_map_filename in list_converted_map_filenames %}
        {% call( redirect_code ) redirected_uri_extra.loop_on_redirected_code() -%}
        # Redirect explicite, issue d'une regle redirect utilisant la valeur enumeree = {{ redirect_code }}
        if ( $redirect_code_{{ redirect_code }}_to_{{ suffix_map }} ) {
            return 		{{ redirect_code }} 	$redirect_to_{{ suffix_map }};
        }
        {% endcall -%}

        {% call( default_redirected_code ) redirected_uri_extra.default_redirected_code() -%}
        # redirect implicite, issue d'une regle mount, utilisant la valeur par default = {{ default_redirected_code }}
        if ( $from_mount_redirect_code_to_{{ suffix_map }} ) {
            return 		{{ default_redirected_code }} 	$redirect_to_{{ suffix_map }};
        }
        {% endcall -%}
    {% else -%}
        # Pas de configuration redirect pour ce serveur
    {% endif -%}

    {% if converted_mount_map_filename in list_converted_map_filenames %}

        rewrite  ^      $prefix_uri_{{ suffix_map }}$suffix_uri_{{ suffix_map }} break;

        # Construction permettant d'utiliser location @backend et de servir les pages d'erreurs
        # Si $uri = egal une page d'erreur, c'est la page d'erreur qui est servie
        try_files               /{{server}}/{{port}}/$url_2_entity_{{ suffix_map }}/$host/$original_uri
                                /{{server}}/{{port}}/$url_2_entity_{{ suffix_map }}/__default__/$original_uri
                                /{{server}}/__default__/$url_2_entity_{{ suffix_map }}/$host/$original_uri
                                /{{server}}/__default__/$url_2_entity_{{ suffix_map }}/__default__/$original_uri
                                /{{server}}/{{port}}/__default__/$host/$original_uri
                                /{{server}}/{{port}}/__default__/__default__/$original_uri
                                /{{server}}/__default__/__default__/$host/$original_uri
                                /{{server}}/__default__/__default__/__default__/$original_uri
                                /__default__/__default__/__default__/$host/$original_uri
                                /__default__/__default__/__default__/__default__/$original_uri
                                @backend;

    {% else %}
        # Pas de configuration mount pour ce serveur
    {% endif -%}

    }
    {% if converted_mount_map_filename in list_converted_map_filenames %}
    location @backend {

        recursive_error_pages on;
        {% call( backend_combination ) backed_uri_extra.loop_on_backend_combination() -%}
        error_page {{ backend_combination[ "index" ] }} = @backend_{{ backend_combination[ "combination" ] }};
        if ( $backend_{{ backend_combination[ "combination" ] }}_{{ suffix_map }} ) {
            return {{ backend_combination[ "index" ] }};
        }
        {% endcall -%}

        {% call( backend_combination ) backed_uri_extra.default_backend_combination() -%}
        # Si aucun $backend_ n'a matche, c'est que la configuration n'existe pas.
        # on utilise alors le backend avec toutes le valeurs par defaut qui renverra
        # l'URL de la page de maintenance (c'est de cette maniere que la page d'erreur
        # s'affichait avant d'eclater en $backend_
        return {{ backend_combination[ "index" ] }};
        {% endcall -%}

    {% if hook_server_configuration.at_server_ending %}
    #  HOOK- : {{ hook_server_configuration.at_server_ending.path }}
    {% include hook_server_configuration.at_server_ending.path with context %}
    # -HOOK  : {{ hook_server_configuration.at_server_ending.path }}
    {% endif %}

    }

    {% call( backend_combination ) backed_uri_extra.loop_on_backend_combination() %}
    location @backend_{{ backend_combination[ "combination" ] }} {

        #proxy_intercept_errors 	on;
        proxy_buffering {{ backend_combination[ "proxy_buffering" ] }};

        proxy_connect_timeout       {{ backend_combination[ "proxy_connect_timeout" ] }};
        proxy_read_timeout          {{ backend_combination[ "proxy_read_timeout" ] }};

        proxy_set_header	Host 		  $host:$server_port;
        proxy_set_header    	X-Real-IP         $remote_addr;
        proxy_set_header        X-Forwarded-Host  $host;
        proxy_set_header    	X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header        X-Forwarded-Proto {% if ssl_configuration %}https{% else %}http{% endif -%};
        proxy_hide_header   	X-Powered-By;

	proxy_set_header	X-MDP-NEW-HTTP-HOST				$mdp_service_redirector_new_http_host_{{ suffix_map }};
	proxy_set_header	X-MDP-NEW-HTTP-HOST-REDIRECTED-HTTP-CODE	$mdp_service_redirector_new_http_host_http_redirected_code_{{ suffix_map }};
	proxy_set_header	X-MDP-NEW-HTTP-HOST-REDIRECTED-HTTP-PROTO	$mdp_service_redirector_new_http_host_http_redirected_proto_{{ suffix_map }};
	proxy_set_header	X-MDP-NEW-HTTP-HOST-REDIRECTED-HTTP-PORT	$mdp_service_redirector_new_http_host_http_redirected_port_{{ suffix_map }};

        proxy_http_version              1.1;

        proxy_set_header 	Upgrade $http_upgrade;
        proxy_set_header 	Connection $connection_upgrade_{{ suffix_map }};

        proxy_redirect 		$proxy_redirect_to_replace_with_port_{{ suffix_map }} $prxfied_and_prefix_uri_{{ suffix_map }};
        proxy_redirect 		$proxy_redirect_to_replace_without_port_{{ suffix_map }} $prxfied_and_prefix_uri_{{ suffix_map }};

        proxy_cookie_domain     $proxy_cookie_domain_to_replace_{{ suffix_map }} $proxy_cookie_domain_replaced_by_{{ suffix_map }};

        proxy_cookie_path       $proxy_cookie_path_to_replace_{{ suffix_map }} $proxy_cookie_path_replaced_by_{{ suffix_map }};
        proxy_cookie_path       $proxy_cookie_path_to_replace_without_suffixed_slash_{{ suffix_map }} $proxy_cookie_path_replaced_by_for_without_suffixed_slash_{{ suffix_map }};

        if ( $not_resolved_backend_{{ suffix_map }} ) {
            set $not_resolved_backend_name not_resolved_backend_{{ suffix_map }};
            set $not_resolved_backend $not_resolved_backend_{{ suffix_map }};
            set $not_resolved_backend_original_url $scheme://$host:$server_port$request_uri;
            set $not_resolved_backend_resolved_url $scheme://$host:$server_port$uri;
            return 		418;
        }

        # Conditions remplies dans ce bloc :
        # La ressource n'est pas dans unmount
        # La ressource n'est pas dans redirect
        # La ressource n'a pas ete trouvee localement sur nginx
        # On teste donc sir la ressource n'est pas non plus montee
        # Si la ressource n'est pas montee, c'est qu'elle n'existe pas
        # On utilise donc return qui contrairement a proxy_passs conserve la valeur
        # de $original_uri
        if ( $not_mounted_{{ suffix_map }} ) {
            return 		404;
        }

        if ( $added_query_string_{{ suffix_map }} ) {

            rewrite ^  $uri?$added_query_string_{{ suffix_map }} break;

        }

        proxy_pass     	$upstream_{{ suffix_map }}$connection_{{ suffix_map }};

    }
    {% endcall %}
    {% endif %}

}

{% if hook_server_configuration.additional_local_maps %}
#  HOOK- : {{ hook_server_configuration.additional_local_maps.path }}
{% include hook_server_configuration.additional_local_maps.path with context %}
# -HOOK  : {{ hook_server_configuration.additional_local_maps.path }}
{% endif %}

{% if converted_unmount_map_filename in list_converted_map_filenames -%}
include {{ root_nginx_configuration }}{{ converted_unmount_map_filename }};
{% else -%}
# Pas de map unmap pour ce serveur
{% endif -%}

{% if converted_redirect_map_filename in list_converted_map_filenames -%}
include {{ root_nginx_configuration }}{{ converted_redirect_map_filename }};
{% else -%}
# Pas de map redirect pour ce serveur
{% endif -%}

{% if converted_mount_map_filename in list_converted_map_filenames -%}
include {{ root_nginx_configuration }}{{ converted_mount_map_filename }};
{% else -%}
# Pas de map mount pour ce serveur
{% endif -%}

{% if converted_url2entity_map_filename in list_converted_map_filenames -%}
include {{ root_nginx_configuration }}{{ converted_url2entity_map_filename }};
{% else -%}
# Pas de map url2entity pour ce serveur
# Creation d'une map par defaut
map $scheme://$host:$server_port$original_uri $url_2_entity_{{ suffix_map }} {

    default     "__default__";

}
{% endif -%}

map $http_upgrade $connection_upgrade_{{ suffix_map }} {

    default     upgrade;
    ''          $connection_{{ suffix_map }};

}

map $cookie_jsessionid $route_cookie_jsessionid_{{ suffix_map }} {
    default     "";
    ~^[^\.]*\.(?P<route>.*)$ $route;
}
