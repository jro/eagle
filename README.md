
# Eagle

is a weak reference to a project from
[The Soul of a New Machine](https://en.wikipedia.org/wiki/The_Soul_of_a_New_Machine),
but mostly I needed a name for the repo. It is an excellent book,
however.

## Design

I wanted to automate the building and deploy of a project so that you
really only need some AWS credentials, a CI account (buildkite), and
your git repo to do CI/CD.

`eagle`
* builds an image for the CI/CD build server
* creates a datacenter
* launches the build server and registers it with the SaaS side of
  buildkite
* then for every deployable event (commit, PR, github deploy, etc)
  buildkite runs the pipeline checked into the project:
  * we'd normally start with unit tests
  * if they pass, we create a server image with the project
    * which runs integration tests to make sure the server is
      answering and returns a particular string
  * if that works, we upload a cloudformation stack to create/update a
    load balancer, and an auto-scale group for our front-end servers
    * if the update fails cloudformation attempts a rollback of the
      stack (not the same as the app but a valid different failure case)
    * if a frontend node fails the LB health check for too many
      minutes the ASG kills it and respawns.
    * on update the ASG gracefully replaces nodes so that there are no
      gaps in uptime
  * and we watch for the page to be updated and match what we have
      checked into source
  * finally we have a passing build pipeline

There are a couple major goals:

* we don't want to have to `run` anything manually except in
  exceptional cases
* we want everything to be in code from infrastructure to the
  application
* we want to push decision making to the places where
  [ground truth](https://en.wikipedia.org/wiki/Ground_truth)
  observations can be made

# Using

## Prerequisites

* A working linux system. packer and terraform are distributed as
  binaries, which is annoying. You can modify `bin/install_deps` if
  you're on a mac and it will _probably_ work.
* bash, curl and unzip

## Accounts

* Fork+clone this repo
* Sign up for aws account [https://aws.amazon.com/]
  * Create IAM account and credentials
  * Record access information
  * Attach "AdministratorAccess" policy
* Sign up for buildkite account [https://buildkite.com/signup]

* Export AWS credentials and buildkite key
```
export AWS_ACCESS_KEY_ID=""
export AWS_SECRET_ACCESS_KEY=""
export BUILDKITE_KEY=""
```

* copy your ssh public key to `terraform/ssh/sshkey.pub`
  * this could be refactored out, but was handy for testing

## Running

* Run `./bin/build_datacenter`
  * this generates the buildkite server ami
  * and the basic networking, IAM policies, ssh keys, etc
  * starts a buildkite-agent server
  * needed to run the "datacenter"

* Running a deploy
  * Go back to [https://buildkite.com/] and create your pipeline. Set it
  so that it pulls the pipeline config from the git repo. Then set the
  github triggers you'd like to use, or do manual builds.
  * When a deploy is triggered the buildkite agent:
    * grabs the code
    * would run unit tests if we had them
    * creates an ami for our "frontend" server using
      * ansible - to configure the server the ami is made from
        * and runs `goss` integration tests on the server
      * packer - to create the ami
    * validates that our deploy has gone out by checking the content
      returned from the load balancer

# Lessons and Todos

* There are some brittle pieces where I'm using `sleep` or using `grep
  and awk` on aws cli output. Those could be made more robust
* Modifying infrastructure from within the infrastructure is
  tricky. Right now cloudformation and terraform are building into
  different subnets. I think they can be merged but it'll take a bit
  of time. Initially, I made a decision not to try and make terraform
  do shared state and use it for everything, but I may revisit that.
* I would like to look at cloudformation signals as a way to signal
  that a `frontend` node is ready. And drive that based on local test
  output.
* This would look a bit different in a real production app that has
  more interdependencies. Maybe not that different for some simple
  webserver + db apps though.
  
Overall, I like how it's turned out so far. It does a lot and stil
feels a bit like magic pushing a commit and see everyting rebuild and
test all within a few minutes. It's resilient to a fair number of
things that break a deploy, or a site. Bits like horizontal scaling
are in a good place to be added in without major restructuring. I
wouldn't call it production ready, but I think I'll probably try to
abstract the _guts_ of this into something I can include as a
submodule in random projects.


  
