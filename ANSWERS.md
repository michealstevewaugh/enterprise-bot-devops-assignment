# Part 5 — Migration to Kubernetes Gateway API

## Migrating 40 Ingress Resources Without Downtime

I would migrate the 40 existing Ingress resources to Kubernetes Gateway API incrementally, keeping the current ingress-nginx controller running until the migration is verified.

First, I would inventory all Ingress resources and document their hosts, paths, TLS settings, annotations, rewrites, authentication, and rate-limiting requirements. I would identify controller-specific behavior that may not have a direct Gateway API equivalent.

Next, I would install the required Gateway API CRDs and a compatible Gateway controller alongside ingress-nginx. I would create the GatewayClass and Gateway resources, then migrate a small number of low-risk routes to HTTPRoute resources. I would validate routing, TLS certificates, backend health, authentication, and application behavior in a staging environment.

After successful testing, I would migrate services in batches and gradually shift traffic using capabilities supported by the chosen controller or load balancer. Throughout the rollout, I would monitor error rates, latency, and backend health. I would retain the existing Ingress configuration and a rollback path until the new routes were stable.

Expected challenges include unsupported annotations, differences in path matching and rewrite behavior, controller-specific policies, TLS configuration issues, and differences in status reporting. I would address these through compatibility testing and incremental rollout.

Finally, I would remove ingress-nginx only after confirming that all routes are migrated, traffic is healthy, and the rollback window has passed.