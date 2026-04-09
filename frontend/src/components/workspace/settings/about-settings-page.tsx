"use client";

import { useEffect, useState } from "react";
import { Streamdown } from "streamdown";

import { getBackendBaseURL } from "@/core/config";
import { env } from "@/env";
import { aboutMarkdown } from "./about-content";

type BuildMetadata = {
  version: string;
  build_time: string;
  branch: string;
  commit: string;
  commit_message: string;
};

type VersionResponse = {
  frontend: BuildMetadata;
  backend: BuildMetadata;
};

const unknownMetadata: BuildMetadata = {
  version: "unknown",
  build_time: "unknown",
  branch: "unknown",
  commit: "unknown",
  commit_message: "unknown",
};

function VersionBlock({
  title,
  value,
}: {
  title: string;
  value: BuildMetadata;
}) {
  return (
    <div className="space-y-3 rounded-lg border p-4">
      <h3 className="text-base font-semibold">{title}</h3>
      <dl className="grid gap-2 text-sm sm:grid-cols-[140px_1fr]">
        <dt className="text-muted-foreground">Version</dt>
        <dd className="break-all font-mono">{value.version}</dd>
        <dt className="text-muted-foreground">Build Time</dt>
        <dd className="break-all font-mono">{value.build_time}</dd>
        <dt className="text-muted-foreground">Branch</dt>
        <dd className="break-all font-mono">{value.branch}</dd>
        <dt className="text-muted-foreground">Commit</dt>
        <dd className="break-all font-mono">{value.commit}</dd>
        <dt className="text-muted-foreground">Commit Message</dt>
        <dd className="break-words">{value.commit_message}</dd>
      </dl>
    </div>
  );
}

export function AboutSettingsPage() {
  const [backendVersion, setBackendVersion] = useState<BuildMetadata>(unknownMetadata);

  useEffect(() => {
    let cancelled = false;

    void fetch(new URL("/api/version", getBackendBaseURL()).toString())
      .then(async (response) => {
        if (!response.ok) {
          throw new Error(`Failed to load version info: ${response.status}`);
        }

        return (await response.json()) as VersionResponse;
      })
      .then((data) => {
        if (!cancelled) {
          setBackendVersion(data.backend ?? unknownMetadata);
        }
      })
      .catch(() => {
        if (!cancelled) {
          setBackendVersion(unknownMetadata);
        }
      });

    return () => {
      cancelled = true;
    };
  }, []);

  const frontendVersion: BuildMetadata = {
    version: env.NEXT_PUBLIC_FRONTEND_VERSION ?? "unknown",
    build_time: env.NEXT_PUBLIC_FRONTEND_BUILD_TIME ?? "unknown",
    branch: env.NEXT_PUBLIC_FRONTEND_BUILD_BRANCH ?? "unknown",
    commit: env.NEXT_PUBLIC_FRONTEND_BUILD_COMMIT ?? "unknown",
    commit_message: env.NEXT_PUBLIC_FRONTEND_BUILD_COMMIT_MESSAGE ?? "unknown",
  };

  return (
    <div className="space-y-6">
      <div className="space-y-4">
        <h2 className="text-lg font-semibold">Version Info</h2>
        <div className="grid gap-4 lg:grid-cols-2">
          <VersionBlock title="Frontend" value={frontendVersion} />
          <VersionBlock title="Backend" value={backendVersion} />
        </div>
      </div>
      <Streamdown>{aboutMarkdown}</Streamdown>
    </div>
  );
}
