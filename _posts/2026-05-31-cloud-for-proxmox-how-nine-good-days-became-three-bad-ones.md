---
date: 2026-05-31
title: "Cloud for ProxMox: How Nine Good Days Became Three Bad Ones"
toc: true
---

So. This one is a bit different.

Most posts in this series are about progress — something worked, here is how, here is what I learned. This one is about something going wrong. Comprehensively wrong. And about what that experience taught me about building with AI, specifically about what happens when you are deliberately trying to do it on the cheap.

## Why this thing exists

Let me give you the full context, because this project actually has three overlapping motivations and they all matter to the story.

**At work.** I work for a Cloud Service Provider / Managed Service Provider company. Big-Tech and the changing political landscape are forcing a serious look at European alternatives. That thought has been simmering for over a year. At some point it stops being abstract and starts being a question worth prototyping.

**At home.** I have been running Proxmox in my homelab for over a year. I already looked at web frontends a while ago — I nearly bought something that lets others create VMs on my Proxmox server. This because I host some small solutions that I co-manage with others. At the moment they fully depend on me for the basics: create a VM, start it, stop it, get remote access. It would be nice to give them a proper self-service layer.

**As an experiment.** The recent spur and rise of AI was another driver. I wanted to get more familiar with it — beyond basic chat and the Copilot functionality in VS Code that I already use, but more in an "agent" way than a "chat" way. [OpenCode](https://opencode.ai) appealed to me specifically because it is open-source. I was also curious whether using a proper orchestrator would open up the possibility to use lighter, simpler LLMs. And layered on top of that: what does it actually take to self-host something like that?

The specific premise was: *can you build something substantial with lighter, cheaper models and good orchestration?* GitHub Copilot with Claude Haiku. OpenCode on the free tier (Big Pickle). Qwen3.6. The question was whether rules, agents, and MCP servers could compensate for not throwing the most expensive model at everything.

I guess I introduced too many variables and risks at once.

Those threads came together into a fork of [proxmox-cloudportal/cloud-platform](https://github.com/proxmox-cloudportal/cloud-platform) — an existing open-source base for a multi-tenant Proxmox portal. I named it `proxmox-isp`. Later renamed to `Cloud for ProxMox` for trademark reasons.

## The good part

I want to give credit where it is due: the first phase was remarkable.

From May 20 to May 25, using [OpenCode](https://opencode.ai) as the orchestrator, the project moved through eight development phases in about five days. Foundation. Bug cleanup. VM lifecycle management. Tenant networking with VLAN/VXLAN isolation. User onboarding. Multi-tenant organisation management with role-based access control. A billing engine with plans and credits. An audit trail. Certificate management.

By May 25, the stack was running live at `https://192.168.2.133`. About 300 commits. 476 tests. A working GUI. Login, dashboard, VM creation — all functional. The solution was fully functional, or at least most of it. Some edge cases may have been lurking, but the core worked.

That pace is genuinely hard to argue with. Even using lightweight models. The AI did what it is good at: keeping conventions consistent across a growing codebase, generating scaffolding without losing the thread, producing test files faster than I could review them. Was it surprising how easily it came together? Frankly, yes. Especially the relative ease.

Which, in retrospect, might have been part of the problem.

## The command that broke everything

On May 26 I decided to start the production hardening phase.

The specific task I gave the AI: separate the frontend from the backend across two LXC containers. Frontend/web on the original container, addressable via its own IP and HTTPS. Backend — database and API — on a new LXC, also accessible over HTTPS. Clean separation. Sensible architecture.

The AI got to work. At some point during that process, the backend got deleted from the original container.

Then the AI tried to rebuild it from the code in the repository. And that is where things unravelled. The code changes that had been made during the session were scattered and incomplete. The AI had been making changes across multiple files without committing atomically, without a verified backup, and without a clear rollback path. What should have been a migration became a reconstruction. And the reconstruction did not work.

No backup had been created beforehand. The working database was gone.

## The thing nobody tells you about Docker in LXC

There is also a more fundamental issue that surfaced during this session, and it explains a lot of the underlying fragility.

Running Docker inside an LXC container is asking for trouble. This is well documented on the internet. It is not a surprising problem if you know to look for it.

The AI apparently did not. It had been struggling with Docker-in-LXC issues throughout the project and at some point seems to have decided to solve this by installing certain components directly on the Proxmox host — rather than cleanly inside the container as intended. This was never made explicitly clear to me. Or I missed it. Subsequent sessions never mentioned it either, despite rules being in place that should have flagged it.

When the infrastructure rebuild happened, we ended up on Ubuntu 26.04 — the cutting-edge new release I was curious about after deciding to move more seriously toward Linux at home. Ubuntu 26.04 ships with hardened AppArmor and seccomp policies. PostgreSQL's socket creation requirements do not play well with unprivileged LXC containers under those policies. The error was direct: `FATAL: could not create any Unix-domain sockets`.

Five workarounds tried. None worked. The old containers were gone. The new ones would not start.

The correct approach — a QEMU VM with Docker on top — is documented on the internet. I learned it the expensive way.

## The repair attempts

May 27. New infrastructure: a proper QEMU VM on Ubuntu 22.04. PostgreSQL socket issues: gone. All eight containers healthy.

Then the next problem surfaced. The git history had diverged. Sixty-six commits on the remote that were not in local, six local commits not on remote. Both sides with unique changes accumulated across sessions without reconciliation.

And the database migrations were broken. SQLAlchemy in the codebase uses async sessions. Alembic expects synchronous engine access. On a fresh deployment, `alembic upgrade head` fails. Every time.

Nine fix attempts across May 27 and 28. Each one solved something and uncovered something else. Conditional drops broke table name references. Fixing the table names surfaced UUID type mismatches. Generating a clean migration from scratch introduced new regressions. Reverting it brought back the old state. Eventually we bypassed Alembic entirely and used direct schema creation — `init_db()` — as a pragmatic workaround.

419 out of 476 tests passing. 87.8%. Declared a working solution.

What I found out later: most of it was mocked. Tests that appeared to pass were not actually exercising the Proxmox infrastructure. They were running against stubs. The 87.8% number was real in the sense that the test suite said so. It was not real in the sense of "I would stake a working deployment on this."

At that point I had lost trust. I was doubling down on affirmations after every step, checking whether what the AI claimed to have done had actually been done. That is not a sustainable working state.

## The cost

Let me be specific about the cost, because it is part of the story.

The build phase ran on the OpenCode free tier (Big Pickle) and GitHub Copilot with Claude Haiku. The premise of the experiment was to stay cheap.

When things went wrong, the token budget evaporated fast. I subscribed to OpenCode Go, using Qwen3.6 Plus. That helped extend things but the underlying problem was not a token problem — it was that each repair attempt introduced new state that constrained the next attempt.

I switched to Claude directly. The token-based subscription. I estimate I burnt around a hundred euros in that phase. Then I moved to the Claude.ai subscription to cap the spend.

So: the build cost almost nothing. The repair cost a hundred euros and is still not finished. The cost of fixing exceeded the cost of creating, by a meaningful margin.

## The decision

By the end of May 28, the honest assessment was:

The accumulated state — diverged git history, bypassed migration tooling, documentation referencing infrastructure that no longer existed, a codebase patched around a deployment problem rather than fixed, and tests that passed against mocks rather than against reality — had become too expensive to maintain and too fragile to fix properly.

Starting over was the only path forward with a working solution at the end of it. So that is what is happening.

The repository `cloudforproxmox-old` is now a read-only archive. Three hundred and three commits have been extracted and documented across five phase files. The new repo (`cloudforproxmox-new`) starts from the original upstream, replays those commits in validated batches on a properly configured VM, and does not advance until each step is confirmed clean.

The HTTPS phase — the identified failure point — is in the plan. But this time it arrives at the end of a verified deployment, not halfway through an unplanned rebuild.

## What the AI got wrong

I want to be specific here, because vague criticism is not useful.

The AI was not wrong about the code. The code worked. Five days and 476 tests is real. The failures were in the operational decisions made around the code: what to destroy, when, what environment to target, whether to verify state before proceeding.

**Rule amnesia within a session.** Not just between sessions, which is expected given how LLMs work. Within a single long session, the AI would forget constraints established at the start. "Do not destroy anything without a confirmed backup" is the kind of instruction that needs to hold for the full session. It did not always. I was already aware of context-window limitations — I should have been more aggressive about reinforcing rules mid-session.

**Silent path changes.** When something was not working — Docker in LXC, for example — the AI found a workaround and used it. Installing components directly on the Proxmox host rather than inside the container as intended. This worked well enough in the moment, and apparently well enough that it was never surfaced as a deviation. By the time it mattered, it was invisible to me.

**Optimistic completion reporting.** A working solution was declared. Tests pass. The solution was working in the sense that the test suite said so. Not in the sense that the Proxmox integration was actually being exercised. The gap between those two things — tests passing against mocks versus tests passing against real infrastructure — was not flagged.

None of this is a verdict on any specific LLM. The lighter models performed within their limits. The problems were in process design: too few checkpoints, insufficient verification of irreversible actions, too much trust in the AI's self-assessment of completeness.

Also: I was being deliberately cheap. Cheaper models, lighter orchestration. That is fine as an experiment premise. But it raises the bar on process discipline because you are working with less headroom for error recovery. I did not account for that trade-off clearly enough.

## Lessons learned

The ones I have actually taken to heart:

**LXC is not the right Docker host.** Use a QEMU VM. Documented, well-known, should have been a constraint from day one.

**Snapshot before every destructive action.** Named Proxmox snapshots after each verified working state. Minimum two in rotation. The name should contain the git commit hash. This is now enforced in the replay process.

**Validate deployments on a temporary VM first.** On major phase transitions, deploy to a separate clean VM, confirm everything works, then deploy to the actual development VM. Then destroy the temporary one. This would have caught the LXC issue before the working stack was destroyed.

**Make the AI confirm before irreversible actions.** Not "deploy the new infrastructure." Instead: "before doing anything that deletes existing state, pause and confirm with me." Explicit, not inferred.

**Context limits are your problem, not just the AI's.** The AI forgetting a rule mid-session is expected. The fix is process discipline on the human side: periodic rule reinforcement, shorter sessions with explicit handoff summaries, more checkpoints.

**Speed creates false confidence.** Five days of easy progress made it feel like recovery would also be easy. It was not. The pace of AI-assisted development is not a reliable signal about the fragility of what it produces.

## Where we are now

As of today it is paused. Honestly, I needed a break from this disaster. I started a different project — [connectwise-to-hibob](https://github.com/peppekerstens/connectwise-to-hibob) — partly for the mental reset and partly for a success that was not contingent on fixing a mess.

I will get back to Cloud for ProxMox. The use case is real — at work, at home, and as an experiment in what lighter AI tooling can actually deliver with the right guardrails. But right now I needed to remember that this stuff can also just work.

I will be relieved when 80% of it is working again. Not against mocks. Against the actual Proxmox infrastructure.

---

*The repos are public at [github.com/peppekerstens](https://github.com/peppekerstens). The archived failed state is `cloudforproxmox-old`. The replay in progress is `cloudforproxmox-new`.*
