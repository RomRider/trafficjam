@test "Deploy the non-swarm environment" {
	docker compose --file "$BATS_TEST_DIRNAME"/docker-compose.yml --project-name trafficjam_test up --detach
	while ! docker exec trafficjam_test docker info &> /dev/null; do
		if (( ++i > 24 )); then
			echo "Timed out waiting for docker in docker to start up. Logs:" >&2
			docker logs trafficjam_test >&2
			exit 1
		fi
		sleep 5
	done
}

@test "Test the non-swarm environment" {
	docker exec trafficjam_test bats /opt/trafficjam/test/test-dind.bats
}

@test "Deploy the swarm environment" {
	docker compose --file "$BATS_TEST_DIRNAME"/docker-compose-swarm.yml --project-name trafficjam_test_swarm up --detach
	while ! docker exec swarm-manager docker info &> /dev/null || ! docker exec swarm-worker docker info &> /dev/null; do
		if (( ++i > 24 )); then
			echo "Timed out waiting for docker in docker to start up. Logs:" >&2
			docker logs swarm-manager
			docker logs swarm-worker
			exit 1
		fi
		sleep 5
	done
	docker exec swarm-manager docker swarm init
	docker exec swarm-worker $(docker exec swarm-manager docker swarm join-token worker | grep "join --token")
	sleep 5
	docker exec swarm-manager docker build -t trafficjam /opt/trafficjam
	docker exec swarm-manager docker build -t whoami /opt/trafficjam/test/containers/whoami
	docker exec swarm-worker docker build -t trafficjam /opt/trafficjam
	docker exec swarm-worker docker build -t whoami /opt/trafficjam/test/containers/whoami
	docker exec swarm-manager docker stack deploy -c /opt/trafficjam/test/docker-compose-dind-swarm.yml test
}

@test "Test the swarm manager" {
	docker exec swarm-manager bats /opt/trafficjam/test/test-dind-swarm.bats
}

@test "Test the swarm worker" {
	docker exec swarm-worker bats /opt/trafficjam/test/test-dind-swarm.bats
}

@test "killing the swarm daemon removes the service" {
	docker exec swarm-manager docker service rm test_trafficjam
	sleep 5
	run bash -c "docker exec swarm-manager docker service ls | grep trafficjam_DEFAULT"
	[ "$status" -eq 1 ]
}

function teardown_file() {
	docker compose --file "$BATS_TEST_DIRNAME"/docker-compose.yml --project-name trafficjam_test down
	docker compose --file "$BATS_TEST_DIRNAME"/docker-compose-swarm.yml --project-name trafficjam_test_swarm down
	docker image rm --force trafficjam_bats trafficjam_test trafficjam_test_whoami
}
