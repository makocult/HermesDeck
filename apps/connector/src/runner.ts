import type { DispatchMessageEvent } from "@hermes-deck/shared";

export interface HermesRunner {
  run(event: DispatchMessageEvent): AsyncIterable<string>;
}

export class MockHermesRunner implements HermesRunner {
  async *run(event: DispatchMessageEvent): AsyncIterable<string> {
    const text = [
      `### ${event.agent_id} received the request\n\n`,
      `Channel: \`${event.channel_id}\`\n\n`,
      `Routing: \`${event.routing_mode}\`\n\n`,
      `Request:\n\n> ${event.content.replace(/\n/g, "\n> ")}\n\n`,
      "Mock result: the Hermes Deck communication path is working. Replace `MockHermesRunner` with a CLI or HTTP runner when the local Hermes execution contract is ready.\n"
    ];
    for (const chunk of text) {
      await delay(160);
      yield chunk;
    }
  }
}

function delay(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
